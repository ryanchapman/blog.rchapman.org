---
title: "ASA: Deny IP due to Land Attack from a.b.c.d to a.b.c.d"
date: "2015-10-28"
categories: 
    - "asa"
    - "land"
    - "attack"
---
<p><em>ASA 5516-X in HA pair, ASA 9.5(1)</em><br/><br/></p>

On an ASA I help manage, the logs were full of messages like "Deny IP due to Land Attack from 1.2.3.4 to 1.2.3.4".  A Land attack is defined as when a packet is received that has the same source and destination IP addresses.  Some definitions also say that the source and destination ports will match, but that was not true in my case.

## Reproducing the issue

To reproduce the issue, I first got my public IP address, which is 1.2.3.4

<pre>
<code class="bash">
rchapman@linux:~$ curl icanhazip.com
1.2.3.4
</code>
</pre>

Next, I set up the ASA to capture all packets it drops

<pre>
<code class="language">
fw1/pri/act# capture cap1 type asp-drop all circular-buffer
fw1/pri/act#
</code>
</pre>

Then I set up a loop to attempt a connect to my public IP address on a strange port (8955) so that I can search for it in the packet capture on the ASA later.

<pre>
<code class="language">
rchapman@linux:~$ while true; do date; nc -w 1 1.2.3.4 8955; sleep 1s; done
Wed Oct 28 20:20:07 EDT 2015
Wed Oct 28 20:20:09 EDT 2015
Wed Oct 28 20:20:11 EDT 2015
[...]
^C
rchapman@linux:~$
</code>
</pre>

The logs confirm that I reproduced the issue

<pre>
<code class="language">
fw1/pri/act# sh log | i Land
Oct 28 2015 20:20:07: %ASA-2-106017: Deny IP due to Land Attack from 1.2.3.4 to 1.2.3.4
Oct 28 2015 20:44:09: %ASA-2-106017: Deny IP due to Land Attack from 1.2.3.4 to 1.2.3.4
Oct 28 2015 20:44:11: %ASA-2-106017: Deny IP due to Land Attack from 1.2.3.4 to 1.2.3.4
[...]
</code>
</pre>

Looking for the dropped packets, I would expect the ASA to say the reason was a Land Attack since that's what the logs say.  Nope, it just says the reason is sp-security-failed.

<pre>
<code class="language">
fw1/pri/act# sh capture cap1 | i 8955
   28: 20:20:07.518924       172.16.230.24.33730 > 1.2.3.4.8955: S 2198057225:2198057225(0) win 29200 <mss 1460,sackOK,timestamp 349841117 0,nop,wscale 7> Drop-reason: (sp-security-failed) Slowpath security checks failed
  207: 20:20:09.527835       172.16.230.24.33736 > 1.2.3.4.8955: S 4274950959:4274950959(0) win 29200 <mss 1460,sackOK,timestamp 349841619 0,nop,wscale 7> Drop-reason: (sp-security-failed) Slowpath security checks failed
  290: 20:20:11.536089       172.16.230.24.33742 > 1.2.3.4.8955: S 4072781874:4072781874(0) win 29200 <mss 1460,sackOK,timestamp 349842121 0,nop,wscale 7> Drop-reason: (sp-security-failed) Slowpath security checks failed
[...]
</code>
</pre>

The packet capture shows the source interface before any NAT happened.  Let's check packet tracer to see if the ASA is NATing the session

<pre>
<code class="language">
fw1/pri/act# packet-tracer input inside tcp 172.16.230.24 33885 1.2.3.4 8955

Phase: 1
Type: ACCESS-LIST
Subtype:
Result: ALLOW
Config:
Implicit Rule
Additional Information:
 Forward Flow based lookup yields rule:
  in  id=0x7fd461841850, priority=1, domain=permit, deny=false
    hits=12075132, user_data=0x0, cs_id=0x0, l3_type=0x8
        src mac=0000.0000.0000, mask=0000.0000.0000
            dst mac=0000.0000.0000, mask=0100.0000.0000
                input_ifc=inside, output_ifc=any

Phase: 2
Type: ROUTE-LOOKUP
Subtype: Resolve Egress Interface
Result: ALLOW
Config:
Additional Information:
found next-hop 1.2.3.1 using egress ifc  outside

Phase: 3
Type: CONN-SETTINGS
Subtype:
Result: ALLOW
Config:
class-map class-default
 match any
 policy-map global_policy
  class class-default
    set connection decrement-ttl
    service-policy global_policy global
    Additional Information:
     Forward Flow based lookup yields rule:
      in  id=0x7fd46c7677f0, priority=7, domain=conn-set, deny=false
        hits=1797218, user_data=0x7fd46e3bcdf0, cs_id=0x0, use_real_addr, flags=0x0, protocol=0
            src ip/id=0.0.0.0, mask=0.0.0.0, port=0, tag=any
                dst ip/id=0.0.0.0, mask=0.0.0.0, port=0, tag=any, dscp=0x0
                    input_ifc=inside, output_ifc=any

Phase: 4
Type: NAT
Subtype:
Result: ALLOW
Config:
object network ny-monitor
 nat (inside,outside) static PAT_Pool
 Additional Information:
 Static translate 172.16.230.24/33885 to 1.2.3.4/33885
  Forward Flow based lookup yields rule:
   in  id=0x7fd461ab94f0, priority=6, domain=nat, deny=false
    hits=19022, user_data=0x7fd461ab5c00, cs_id=0x0, flags=0x0, protocol=0
        src ip/id=172.16.230.24, mask=255.255.255.254, port=0, tag=any
            dst ip/id=0.0.0.0, mask=0.0.0.0, port=0, tag=any, dscp=0x0
                input_ifc=inside, output_ifc=outside

Phase: 5
Type: NAT
Subtype: per-session
Result: ALLOW
Config:
Additional Information:
 Forward Flow based lookup yields rule:
  in  id=0x7fd4611bf480, priority=0, domain=nat-per-session, deny=false
    hits=874821, user_data=0x0, cs_id=0x0, reverse, use_real_addr, flags=0x0, protocol=6
        src ip/id=0.0.0.0, mask=0.0.0.0, port=0, tag=any
            dst ip/id=0.0.0.0, mask=0.0.0.0, port=0, tag=any, dscp=0x0
                input_ifc=any, output_ifc=any

Phase: 6
Type: IP-OPTIONS
Subtype:
Result: ALLOW
Config:
Additional Information:
 Forward Flow based lookup yields rule:
  in  id=0x7fd46146a980, priority=0, domain=inspect-ip-options, deny=true
    hits=98075, user_data=0x0, cs_id=0x0, reverse, flags=0x0, protocol=0
        src ip/id=0.0.0.0, mask=0.0.0.0, port=0, tag=any
            dst ip/id=0.0.0.0, mask=0.0.0.0, port=0, tag=any, dscp=0x0
                input_ifc=inside, output_ifc=any

Phase: 7
Type: FOVER
Subtype: standby-update
Result: ALLOW
Config:
Additional Information:
 Forward Flow based lookup yields rule:
  in  id=0x7fd461b92d20, priority=20, domain=lu, deny=false
    hits=804138, user_data=0x0, cs_id=0x0, flags=0x0, protocol=6
        src ip/id=0.0.0.0, mask=0.0.0.0, port=0, tag=any
            dst ip/id=0.0.0.0, mask=0.0.0.0, port=0, tag=any, dscp=0x0
                input_ifc=inside, output_ifc=any

Phase: 8
Type: USER-STATISTICS
Subtype: user-statistics
Result: ALLOW
Config:
Additional Information:
 Forward Flow based lookup yields rule:
  out id=0x7fd46e3b3df0, priority=0, domain=user-statistics, deny=false
    hits=1843176, user_data=0x7fd4611d29a0, cs_id=0x0, reverse, flags=0x0, protocol=0
        src ip/id=0.0.0.0, mask=0.0.0.0, port=0, tag=any
            dst ip/id=0.0.0.0, mask=0.0.0.0, port=0, tag=any, dscp=0x0
                input_ifc=any, output_ifc=outside

Result:
input-interface: inside
input-status: up
input-line-status: up
output-interface: outside
output-status: up
output-line-status: up
Action: drop
Drop-reason: (sp-security-failed) Slowpath security checks failed

fw1/pri/act#
</code>
</pre>

It is. Phase 4 of the packet trace shows a translation from <tt>172.16.230.24 / 33885</tt> to <tt>1.2.3.4 / 33885</tt>

## The fix

Put a NONAT (NAT exemption) rule in place

<pre>
<code class="language">
fw1/pri/act# sh run object id ny-monitor
object network linux1
 subnet 172.16.230.24 255.255.255.254
fw1/pri/act#
fw1/pri/act# sh run object id PAT_Pool
 object network PAT_Pool
  range 1.2.3.4 1.2.3.90
fw1/pri/act#
fw1/pri/act# nat (inside,outside) source static linux1 linux1 destination static PAT_Pool PAT_Pool no-proxy-arp route-lookup
</code>
</pre>

What this says is "if the source ip address is 172.16.230.24 and the destination ip address is in the range 1.2.3.4 through 1.2.3.90," then ignore this NAT rule:

<pre>
<code class="language">
fw1/pri/act# sh run nat
[...]
  object network linux1
   nat (inside,outside) static PAT_Pool
</code>
</pre>

I tested by again creating lots of connections to 1.2.3.4 from the linux machine and now I don't see Land Attack messages in the ASA system log.  Another packet trace confirms that the NAT exclusion is working.

<pre>
<code class="language">
fw1/sec/act# packet-tracer input inside tcp 172.16.230.24 33885 1.2.3.4 80

Phase: 1
Type: ACCESS-LIST
Subtype:
Result: ALLOW
Config:
Implicit Rule
Additional Information:
MAC Access list

Phase: 2
Type: ROUTE-LOOKUP
Subtype: Resolve Egress Interface
Result: ALLOW
Config:
Additional Information:
found next-hop 1.2.3.1 using egress ifc  outside

Phase: 3
Type: UN-NAT
Subtype: static
Result: ALLOW
Config:
nat (inside,outside) source static linux1 linux1 destination static PAT_Pool PAT_Pool no-proxy-arp route-lookup
Additional Information:
NAT divert to egress interface outside
Untranslate 1.2.3.4/8955 to 1.2.3.4/8955

Phase: 4
Type: CONN-SETTINGS
Subtype:
Result: ALLOW
Config:
class-map class-default
 match any
 policy-map global_policy
  class class-default
    set connection decrement-ttl
    service-policy global_policy global
    Additional Information:

Phase: 5
Type: NAT
Subtype:
Result: ALLOW
Config:
nat (inside,outside) source static linux1 linux1 destination static PAT_Pool PAT_Pool no-proxy-arp route-lookup
Additional Information:
Static translate 172.16.230.24/33885 to 172.16.230.24/33885

Phase: 6
Type: NAT
Subtype: per-session
Result: ALLOW
Config:
Additional Information:

Phase: 7
Type: IP-OPTIONS
Subtype:
Result: ALLOW
Config:
Additional Information:

Phase: 8
Type: FOVER
Subtype: standby-update
Result: ALLOW
Config:
Additional Information:

Phase: 9
Type: NAT
Subtype: rpf-check
Result: ALLOW
Config:
nat (inside,outside) source static linux1 linux1 destination static PAT_Pool PAT_Pool no-proxy-arp route-lookup
Additional Information:

Phase: 10
Type: USER-STATISTICS
Subtype: user-statistics
Result: ALLOW
Config:
Additional Information:

Phase: 11
Type: NAT
Subtype: per-session
Result: ALLOW
Config:
Additional Information:

Phase: 12
Type: IP-OPTIONS
Subtype:
Result: ALLOW
Config:
Additional Information:

Phase: 13
Type: USER-STATISTICS
Subtype: user-statistics
Result: ALLOW
Config:
Additional Information:

Phase: 14
Type: FLOW-CREATION
Subtype:
Result: ALLOW
Config:
Additional Information:
New flow created with id 2160780, packet dispatched to next module

Result:
input-interface: inside
input-status: up
input-line-status: up
output-interface: outside
output-status: up
output-line-status: up
Action: allow

fw1/pri/act#
</code>
</pre>




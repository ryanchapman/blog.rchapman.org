#!/bin/bash -

TRUE=0
FALSE=1

PARENTWD=$(dirname `pwd`)
REPONAME=$(basename `pwd`)

function logit
{
    if [[ "${1}" == "FATAL" ]]; then
        fatal="FATAL"
        shift
    fi
    echo -n "$(date '+%b %d %H:%M:%S.%N %Z') $(basename -- $0)[$$]: "
    if [[ "${fatal}" == "FATAL" ]]; then echo -n "${fatal} "; fi
    echo "$*"
    if [[ "${fatal}" == "FATAL" ]]; then exit 1; fi
}

function run_ignerr
{
    _run warn $*
}

function run
{
    _run fatal $*
}

function _run
{
    if [[ $1 == fatal ]]; then
        errors_fatal=$TRUE
    else
        errors_fatal=$FALSE
    fi
    shift
    logit "$*"
    eval "$*"
    rc=$?
    logit "$* returned $rc"
    # fail hard and fast
    if [[ $rc != 0 && $errors_fatal == $TRUE ]]; then
        pwd
        exit 1
    fi
    return $rc
}

function local
{
    run hugo
    run hugo server --baseUrl=http://localhost:1313/ --renderToDisk --verbose
}

function deploy
{
    run hugo
    run cp CNAME public
    run git add -A
    if ! git diff-index --cached --quiet HEAD --ignore-submodules; then
        git commit -m "changes"
    fi
    run git status
    run git push origin master
    logit "Checking if we need to delete remote gh-pages branch"
    run git branch -r | grep gh-pages >/dev/null 
    if [[ $? == 0 ]]; then
        logit "Checking if we need to delete remote gh-pages branch: yes"
        run git push origin --delete gh-pages
    else
        logit "Checking if we need to delete remote gh-pages branch: no"
    fi
    run git subtree push --prefix=public git@github.com:ryanchapman/test2.git gh-pages
}

#################################
# main
#################################

function main () {
    func_to_exec=${1}
    type ${func_to_exec} 2>&1 | grep -q 'function' >&/dev/null || {
        logit "$(basename $0): ERROR: function '${func_to_exec}' not found."
        exit 1
    }

    shift
    ${func_to_exec} $*
    echo
}

# did someone source this file or execute it directly?  If not sourced, then we are responsible for
# executing main().  Files sourcing this one are responsible for calling main()
sourced=$FALSE
[ "$0" = "$BASH_SOURCE" ] || sourced=$TRUE

if [[ $sourced == $FALSE ]]; then
    main $*
fi


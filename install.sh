#!/bin/bash

####################################################################################################
#
# Example:
#    Deploy and run cli against master
#         ./cli-setup.sh
#    Deploy and run cli against master
#         ./cli-setup.sh
#    Local deployment using the current branch debugging enabled (DEVELOPMENT ONLY!)
#         ./cli-setup.sh -l -d -b=$(git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/')
#
####################################################################################################

set -o pipefail

start_time=$(date +"%s.%N")

package_name="Example-Package"
package_repo="github.com/platform9/Example-Package"


assert() {
    if [ $# -gt 0 ]; then stdout_log "ASSERT: ${1}"; fi
    if [[ -f ${log_file} ]]; then
        echo -e "\n\n"
	echo ""
	echo "Installation failed, Here are the last 10 lines from the log"
	echo "The full installation log is available at ${log_file}"
	echo "If more information is needed re-run the install with --debug"
	echo "$(tail ${log_file})"
    else
	echo "Installation ${package_name} failed prior to log file being created"
	echo "Try re-running with --debug"
    fi
    exit 1
}

debugging() {
    # This function handles formatting all debugging text.
    # debugging is always sent to the logfile.
    # If no debug flag, this function will silently log debugging messages.
    # If debug flag is present then debug output will be formatted then echo'd to stdout and sent to logfile.
    # If debug flag is present messages sent to stdout_log will be forwarded to debugging for consistancy.

    # Avoid error if bc is not installed yet
    if (which bc > /dev/null 2>&1); then
	output="DEBUGGING: $(date +"%T") : $(bc <<<$(date +"%s.%N")-${start_time}) :$(basename $0) : ${1}"
    else
	output="DEBUGGING: $(date +"%T") : $(basename $0) : ${1}"
    fi

    if [ -f ${log_file} ]; then
	echo "${output}" 2>&1 >> ${log_file}
    fi
    if [[ ${debug_flag} ]]; then
	echo "${output}" 
    fi
}

stdout_log(){
    # If debug flag is present messages sent to stdout_log will be forwarded to debugging for consistancy.
    if [[ ${debug_flag} ]]; then
	debugging "$1"
    else
        echo "$1"
	debugging "$1"
    fi
}

parse_args() {
    for i in "$@"; do
      case $i in
	-h|--help)
	    echo "Usage: $(basename $0)"
 	    echo "	  [--branch=]"
 	    echo "	  [--dev] Installs from local source code for each project in editable mode."
 	    echo "                This assumes you have provided all source code in the correct locations"
 	    echo "	  [--local] Installs local source code in the same directory"
 	    echo "	  [-d|--debug]"
 	    echo ""
	    echo ""
	    exit 0
	    shift
	    ;;
	--branch=*)
	    if [[ -n ${i#*=} ]]; then
	      branch="${i#*=}"
	    else
		assert "'--branch=' Requires a Branch name"
	    fi
	    shift
	    ;;
	-d|--debug)
	    debug_flag="${i#*=}"
	    shift
	    ;;
	--dev)
	    dev_build="--dev"
	    shift
	    ;;
	--local)
	    run_local="--local"
	    shift
	    ;;
	*)
	echo "$i is not a valid command line option."
	echo ""
	echo "For help, please use $0 -h"
	echo ""
	exit 1
	;;
	esac
	shift
    done
}

init_venv_python() {
    debugging "Virtualenv: ${venv} doesn't not exist, Configuring."
    for ver in {3,2,''}; do #ensure python3 is first
	debugging "Checking Python${ver}: $(which python${ver})"
        if (which python${ver} > /dev/null 2>&1); then
	    python_version="$(python${ver} <<< 'import sys; print(sys.version_info[0])')"
	    stdout_log "Python Version Selected: python${python_version}"
	    break
        fi
    done

    if [[ ${python_version} == 2 ]]; then
        pyver="";
    else
        pyver="3";
    fi
    stdout_log "Initializing Virtual Environment using Python ${python_version}"
    #Validate and initialize virtualenv
    if ! (virtualenv --version > /dev/null 2>&1); then
        debugging "Validating pip"
	if ! which pip > /dev/null 2>&1; then
            debugging "ERROR: missing package: pip (attempting to install using get-pip.py)"
            curl -s -o ${pip_path} ${pip_url}
            if [ ! -r ${pip_path} ]; then assert "failed to download get-pip.py (from ${pip_url})"; fi

            if ! (python${pyver} "${pip_path}"); then
                debugging "ERROR: failed to install package: pip (attempting to install via 'sudo get-pip.py')"
                if (sudo python${pyver} "${pip_path}" > /dev/null 2>&1); then
                    assert "Please install package: pip"
                fi
            fi
        fi
	debugging "ERROR: missing python package: virtualenv (attempting to install via 'pip install virtualenv')"
        # Attemping to Install virtualenv
        if ! (pip${pyver} install virtualenv > /dev/null 2>&1); then
            debugging "ERROR: failed to install python package (attempting to install via 'sudo pip install virtualenv')"
            if ! (sudo pip${pyver} install virtualenv > /dev/null 2>&1); then
                assert "Please install the 'virtualenv' module using 'pip install virtualenv'"
            fi
        fi
    fi
    if ! (virtualenv -p python${pyver} --system-site-packages ${venv} > /dev/null 2>&1); then
        assert "Creation of virtual environment failed"
    fi
    debugging "venv_python: ${venv_python}"
    if [ ! -r ${venv_python} ]; then assert "failed to initialize virtual environment"; fi
}


## main
# Set the path so double quotes don't use the litteral '~'
basedir=$(dirname ~/${package_name}/.)
log_file="${basedir}/log/install.log"
bin="${basedir}/bin"
venv="${basedir}/venv"
state_dirs="${bin} ${venv} ${basedir}/log"

parse_args "$@"
# initialize installation directory
initialize_basedir

debugging "CLFs: $*"

# Set global variables
	
if [ -z ${branch} ]; then
    branch=$(git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/')
    if [ $? -ne 0 ]; then
	branch=master
    fi
fi
debugging "Setting environment variables to be passed to installers"

if [[ -z ${run_local} && -z ${dev_build} ]]; then
    cli_url="git+git://${package_repo}.git@${branch}#egg=${package_name}"
elif [[ -n ${dev_build} ]]; then
    cli_url="-e .[test]"
elif [[ -n ${run_local} ]]; then
    cli_url="."
fi
debugging "branch: ${branch}"
debugging "cli_url: ${cli_url}"

pip_path=${basedir}/get_pip.py
venv_python="${venv}/bin/python"
venv_activate="${venv}/bin/activate"
pip_url="https://bootstrap.pypa.io/get-pip.py"
cli_entrypoint=$(dirname ${venv_python})/express
cli_exec=${bin}/${package_name}


# configure python virtual environment
stdout_log "Configuring virtualenv"
if [ ! -f "${venv_activate}" ]; then
    init_venv_python
else
    stdout_log "INFO: using exising virtual environment"
fi

stdout_log "Upgrade pip"
if ! (${venv_python} -m pip install --upgrade --ignore-installed pip setuptools wheel > /dev/null 2>&1); then
    assert "Pip upgrade failed"; fi

stdout_log "Installing ${package_name}"
if ! (${venv_python} -m pip install --upgrade --ignore-installed ${cli_url} > /dev/null 2>&1); then
    assert "Installation of ${package_name}"; fi

if ! (${cli_entrypoint} --help > /dev/null 2>&1); then
    assert "Base Installation of ${package_name}"; fi
if [ ! -f ${cli_exec} ]; then
    stdout_log "Create ${package_name} symlink"
    if [ -L ${cli_exec} ]; then
	if ! (rm ${cli_exec} > /dev/null 2>&1); then
	    assert "Failed to remove existing symlink: ${cli_exec}"; fi
    fi 
    if ! (ln -s ${cli_entrypoint} ${cli_exec} > /dev/null 2>&1); then
	    assert "Failed to create ${package_name} symlink: ${cli_exec}"; fi
else
    stdout_log "${package_name} symlink already exist"
fi
if ! (${cli_exec} --help > /dev/null 2>&1); then
    assert "Installation of ${package_name} Failed"; fi

echo ""
echo ""
echo ""
echo ""
eval "${cli_exec}" --help

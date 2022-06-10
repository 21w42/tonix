pragma ton-solidity >= 0.61.0;

import "Shell.sol";

contract set is Shell {

    function main(svm sv_in) external pure returns (svm sv) {
        sv = sv_in;
        s_proc p = sv.cur_proc;
        for (uint16 i = 0; i < 12; i++) {
            p.puts(vmem.vmem_fetch_page(sv.vmem[1], i));
        }
        sv.cur_proc = p;
    }

    function _builtin_help() internal pure override returns (BuiltinHelp) {
        return BuiltinHelp(
"set",
"[-abefhkmnptuvxBCHP] [--] [arg ...]",
"Set or unset values of shell options and positional parameters.",
"Change the value of shell attributes and positional parameters, or display the names and values of shell variables.",
"-a  Mark variables which are modified or created for export.\n\
-b  Notify of job termination immediately.\n\
-e  Exit immediately if a command exits with a non-zero status.\n\
-f  Disable file name generation (globbing).\n\
-h  Remember the location of commands as they are looked up.\n\
-k  All assignment arguments are placed in the environment for a command, not just those that precede the command name.\n\
-m  Job control is enabled.\n\
-n  Read commands but do not execute them.\n\
-p  Turned on whenever the real and effective user ids do not match. Disables processing of the $ENV file and importing\n\
    of shell functions.  Turning this option off causes the effective uid and gid to be set to the real uid and gid.\n\
-t  Exit after reading and executing one command.\n\
-u  Treat unset variables as an error when substituting.\n\
-v  Print shell input lines as they are read.\n\
-x  Print commands and their arguments as they are executed.\n\
-B  the shell will perform brace expansion\n\
-C  If set, disallow existing regular files to be overwritten by redirection of output.\n\
-E  If set, the ERR trap is inherited by shell functions.\n\
-H  Enable ! style history substitution.  This flag is on by default when the shell is interactive.\n\
-P  If set, do not resolve symbolic links when executing commands such as cd which change the current directory.\n\
-T  If set, the DEBUG and RETURN traps are inherited by shell functions.\n\
--  Assign any remaining arguments to the positional parameters. If there are no remaining arguments, the positional\n\
    parameters are unset.\n\
-   Assign any remaining arguments to the positional parameters. The -x and -v options are turned off.",
"Using + rather than - causes these flags to be turned off. The flags can also be used upon invocation of the shell.\n\
The current set of flags may be found in $-. The remaining n ARGs are positional parameters and are assigned, in order,\n\
to $1, $2, .. $n. If no ARGs are given, all shell variables are printed.",
"Returns success unless an invalid option is given.");
    }
}

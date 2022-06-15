pragma ton-solidity >= 0.61.1;

import "pbuiltin_special.sol";

contract export is pbuiltin_special {

    function _retrieve_pages(shell_env e, s_proc p) internal pure override returns (mapping (uint8 => string) pages) {
        if (p.flag_set("f"))
            pages[9] = e.e_exports;
        else
            pages[8] = e.e_exports;
    }

    function _update_shell_env(shell_env e_in, uint8, string page) internal pure override returns (shell_env e) {
        e = e_in;
        e.e_exports = page;
    }

    function _print(s_proc p_in, string[] params, string page) internal pure override returns (s_proc p) {
        p = p_in;
        bool functions_only = p.flag_set("f");
        string sattrs = "-x";
        if (functions_only)
            sattrs.append("-f");
            if (params.empty()) {
                (string[] lines, ) = page.split("\n");
                for (string line: lines) {
                    (string attrs, ) = line.csplit(" ");
                    if (vars.match_attr_set(sattrs, attrs))
                        p.puts(vars.print_reusable(line));
                }
            }
            for (string param: params) {
                (string name, ) = param.csplit("=");
                string cur_record = vars.get_pool_record(name, page);
                if (!cur_record.empty()) {
                    (string cur_attrs, ) = cur_record.csplit(" ");
                    if (vars.match_attr_set(sattrs, cur_attrs))
                        p.puts(vars.print_reusable(cur_record));
                } else
                    p.perror(name + " not found");
            }
    }
    function _modify(s_proc p_in, string[] params, string page_in) internal pure override returns (s_proc p, string page) {
        p = p_in;
        bool functions_only = p.flag_set("f");
        bool unexport = p.flag_set("n");

        string sattrs = unexport ? "+x" : "-x";
        page = page_in;
        if (functions_only)
            sattrs.append("-f");
        for (string param: params)
            page = vars.set_var(sattrs, param, page);
    }

    function _builtin_help() internal pure override returns (BuiltinHelp) {
        return BuiltinHelp(
"export",
"[-fn] [name[=value] ...] or export -p",
"Set export attribute for shell variables.",
"Marks each NAME for automatic export to the environment of subsequently executed commands. If VALUE is supplied,\n\
assign VALUE before exporting.",
"-f        refer to shell functions\n\
-n        remove the export property from each NAME\n\
-p        display a list of all exported variables and functions",
"An argument of `--' disables further option processing.",
"Returns success unless an invalid option is given or NAME is invalid.");
    }
}

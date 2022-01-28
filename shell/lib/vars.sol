pragma ton-solidity >= 0.56.0;

import "fmt.sol";

library vars {

    // The various attributes that a given variable can have
    uint16 constant ATTR_EXPORTED   = 1; // export to environment
    uint16 constant ATTR_READONLY   = 2; // cannot change
    uint16 constant ATTR_ARRAY      = 4; // value is an array
    uint16 constant ATTR_FUNCTION   = 8; // value is a function
    uint16 constant ATTR_INTEGER	= 16;// internal representation is int
    uint16 constant ATTR_LOCAL      = 32;// variable is local to a function
    uint16 constant ATTR_ASSOC      = 64;// variable is an associative array
    uint16 constant ATTR_TRACE  	= 128;// function is traced with DEBUG trap
    uint16 constant ATTR_MASK_USER  = 255;
    uint16 constant ATTR_INVISIBLE  = 256;  // cannot see
    uint16 constant ATTR_NO_UNSET   = 512;	// cannot unset
    uint16 constant ATTR_NO_ASSIGN  = 1024;	// assignment not allowed
    uint16 constant ATTR_IMPORTED   = 2048;	// came from environment
    uint16 constant ATTR_SPECIAL    = 4096;	// requires special handling
    uint16 constant ATTR_MASK_INT   = 0xFF00;
    uint16 constant ATTR_TEMP_VAR	= 8192;	// variable came from the temp environment
    uint16 constant ATTR_PROPAGATE  = 16384;// propagate to previous scope
    uint16 constant ATTR_MASK_SCOPE = 24576;

    uint16 constant W_NONE      = 0;
    uint16 constant W_COLON     = 1;
    uint16 constant W_DQUOTE    = 2;
    uint16 constant W_PAREN     = 3;
    uint16 constant W_BRACE     = 4;
    uint16 constant W_SQUARE    = 5;
    uint16 constant W_SPACE     = 6;
    uint16 constant W_NEWLINE   = 7;
    uint16 constant W_SQUOTE    = 8;
    uint16 constant W_ARRAY     = 9;
    uint16 constant W_HASHMAP   = 10;
    uint16 constant W_FUNCTION  = 11;

    function fetch_value(string key, uint16 delimiter, string page) internal returns (string value) {
        string key_pattern = wrap(key, W_SQUARE);
        (string val_pattern_start, string val_pattern_end) = wrap_symbols(delimiter);
        return stdio.strval(page, key_pattern + "=" + val_pattern_start, val_pattern_end);
    }

    function val(string key, string page) internal returns (string value) {
        return fetch_value(key, W_DQUOTE, page);
    }

    function function_body(string key, string page) internal returns (string value) {
        return fetch_value(key, W_BRACE, page);
    }

    function get_map_value(string map_name, string page) internal returns (string value) {
        return unwrap(fetch_value(map_name, W_PAREN, page));
    }

    function item_value(string item) internal returns (string, string) {
        (string key, string value) = stdio.strsplit(item, "=");
        return (unwrap(key), unwrap(value));
    }

    function match_attr_set(string part_attrs, string cur_attrs) internal returns (bool) {
        uint part_attrs_len = part_attrs.byteLength() / 2;
        for (uint i = 0; i < part_attrs_len; i++) {
            string attr_sign = part_attrs.substr(i * 2, 1);
            string attr_sym = part_attrs.substr(i * 2 + 1, 1);

            bool flag_cur = stdio.strchr(cur_attrs, attr_sym) > 0;
            bool flag_match = (flag_cur && attr_sign == "-");
            if (!flag_match)
                return false;
        }
        return true;
    }

    function meld_attr_set(string part_attrs, string cur_attrs) internal returns (string res) {
        res = cur_attrs;
        uint part_attrs_len = part_attrs.byteLength() / 2;
        for (uint i = 0; i < part_attrs_len; i++) {
            string attr_sign = part_attrs.substr(i * 2, 1);
            string attr_sym = part_attrs.substr(i * 2 + 1, 1);

            bool flag_cur = stdio.strchr(cur_attrs, attr_sym) > 0;
            if (!flag_cur && attr_sign == "-")
                res.append(attr_sym);
            else if (flag_cur && attr_sign == "+")
                res = stdio.translate(res, attr_sym, "");
        }
        if (res == "-")
            return "--";
        if (res.byteLength() > 2 && res.substr(0, 2) == "--")
            return res.substr(1);
    }

    function var_record(string attrs, string name, string value) internal returns (string) {
        uint16 mask = get_mask_ext(attrs);
        if (attrs == "")
            attrs = "--";
        bool is_function = stdio.strchr(attrs, "f") > 0;
        string var_value = value.empty() ? "" : "=";
        if (!value.empty())
            var_value.append(wrap(value, (mask & ATTR_ASSOC + ATTR_ARRAY) > 0 ? W_PAREN : W_DQUOTE));
        return is_function ?
            (name + " () " + wrap(value, W_FUNCTION)) :
            attrs + " " + wrap(name, W_SQUARE) + var_value;
    }

    function split_var_record(string line) internal returns (string, string, string) {
        (string decl, string value) = stdio.strsplit(line, "=");
        (string attrs, string name) = stdio.strsplit(decl, " ");
        return (attrs, unwrap(name), unwrap(value));
    }

    function get_pool_record(string name, string pool) internal returns (string) {
        string pat = wrap(name, W_SQUARE);
        (string[] lines, ) = stdio.split(pool, "\n");
        for (string line: lines)
            if (stdio.strstr(line, pat) > 0)
                return line;
    }

    function print_reusable(string line) internal returns (string) {
        (string attrs, string name, string value) = split_var_record(line);
        bool is_function = stdio.strchr(attrs, "f") > 0;
        string var_value = value.empty() ? "" : "=" + value;
        return is_function ?
            (name + " ()" + wrap(fmt.indent(stdio.translate(value, ";", "\n"), 4, "\n"), W_FUNCTION)) :
            "declare " + attrs + " " + name + var_value + "\n";
    }

    function as_var_list(string[][2] entries) internal returns (string res) {
        for (uint i = 0; i < entries.length; i++)
            res.append("-- " + wrap(entries[i][0], W_SQUARE) + (entries[i][1].empty() ? "" : ("=" + wrap(entries[i][1], W_DQUOTE))) + "\n");
    }

    function as_hashmap(string name, string[][2] entries) internal returns (string res) {
        string body;
        for (uint i = 0; i < entries.length; i++)
            body.append(wrap(entries[i][0], W_SQUARE) + "=" + wrap(entries[i][1], W_DQUOTE) + " ");
        res = "-A " + wrap(name, W_SQUARE) + "=" + wrap(body, W_HASHMAP);
    }

    function as_indexed_array(string name, string value, string ifs) internal returns (string res) {
        string body;
        (string[] fields, uint n_fields) = stdio.split(value, ifs);
        for (uint i = 0; i < n_fields; i++)
            body.append(format("[{}]=\"{}\" ", i, fields[i]));
        res = "-a " + wrap(name, W_SQUARE) + "=" + wrap(body, W_ARRAY);
    }

    function encode_item(string key, string value) internal returns (string res) {
        res = wrap(key, W_SQUARE) + "=" + wrap(value, W_DQUOTE);
    }

    function as_map(string value) internal returns (string res) {
        res = wrap(value, W_HASHMAP);
    }

    function get_array_name(string value, string context) internal returns (string name) {
        (string[] lines, ) = stdio.split(context, "\n");
        string val_pattern = wrap(value, vars.W_SPACE);
        for (string line: lines)
            if (stdio.strstr(line, val_pattern) > 0)
                return stdio.strval(line, "[", "]");
    }

    function set_item_value(string name, string value, string page) internal returns (string) {
        string cur_value = val(name, page);
        string new_record = encode_item(name, value);
        return cur_value.empty() ? page + " " + new_record : stdio.translate(page, encode_item(name, cur_value), new_record);
    }

    function set_var(string attrs, string token, string pg) internal returns (string page) {
        (string name, string value) = stdio.strsplit(token, "=");
        string cur_record = get_pool_record(name, pg);
        string new_record = var_record(attrs, name, value);
        if (!cur_record.empty()) {
            (string cur_attrs, ) = stdio.strsplit(cur_record, " ");
            (, string cur_value) = stdio.strsplit(cur_record, "=");
            string new_value = !value.empty() ? value : !cur_value.empty() ? unwrap(cur_value) : "";
            new_record = var_record(meld_attr_set(attrs, cur_attrs), name, new_value);
            page = stdio.translate(pg, cur_record, new_record);
        } else
            page = pg + new_record + "\n";
    }

    function get_mask_ext(string s_attrs) internal returns (uint16 mask) {
        uint len = s_attrs.byteLength();
        for (uint i = 0; i < len; i++) {
            string c = s_attrs.substr(i, 1);
            if (c == "x") mask |= ATTR_EXPORTED;
            if (c == "r") mask |= ATTR_READONLY;
            if (c == "a") mask |= ATTR_ARRAY;
            if (c == "f") mask |= ATTR_FUNCTION;
            if (c == "i") mask |= ATTR_INTEGER;
            if (c == "l") mask |= ATTR_LOCAL;
            if (c == "A") mask |= ATTR_ASSOC;
            if (c == "t") mask |= ATTR_TRACE;
        }
    }

    function mask_base_type(uint16 mask) internal returns (string s_attrs) {
        if ((mask & ATTR_ARRAY) > 0) return "a";
        if ((mask & ATTR_FUNCTION) > 0) return "f";
        if ((mask & ATTR_ASSOC) > 0) return "A";
        return "-";
    }

    function mask_str(uint16 mask) internal returns (string s_attrs) {
        s_attrs = mask_base_type(mask);
        if ((mask & ATTR_INTEGER) > 0) s_attrs.append("i");
        if ((mask & ATTR_EXPORTED) > 0) s_attrs.append("x");
        if ((mask & ATTR_READONLY) > 0) s_attrs.append("r");
        if ((mask & ATTR_LOCAL) > 0) s_attrs.append("l");
        if ((mask & ATTR_TRACE) > 0) s_attrs.append("t");
        if (s_attrs == "-") s_attrs.append("-");
    }

    function wrap_symbols(uint16 to) internal returns (string start, string end) {
        if (to == W_COLON)
            return (":", ":");
        else if (to == W_DQUOTE)
            return ("\"", "\"");
        else if (to == W_PAREN)
            return ("(", ")");
        else if (to == W_BRACE)
            return ("{", "}");
        else if (to == W_SQUARE)
            return ("[", "]");
        else if (to == W_SPACE)
            return (" ", " ");
        else if (to == W_NEWLINE)
            return ("\n", "\n");
        else if (to == W_SQUOTE)
            return ("\'", "\'");
        else if (to == W_ARRAY)
            return ("( ", " )");
        else if (to == W_HASHMAP)
            return ("( ", " )");
        else if (to == W_FUNCTION)
            return ("", "\n");
    }

    function wrap(string s, uint16 to) internal returns (string res) {
        if (to == W_COLON)
            return ":" + s + ":";
        else if (to == W_DQUOTE)
            return "\"" + s + "\"";
        else if (to == W_PAREN)
            return "(" + s + ")";
        else if (to == W_BRACE)
            return "{" + s + "}";
        else if (to == W_SQUARE)
            return "[" + s + "]";
        else if (to == W_SPACE)
            return " " + s + " ";
        else if (to == W_NEWLINE)
            return "\n" + s + "\n";
        else if (to == W_SQUOTE)
            return "\'" + s + "\'";
        else if (to == W_ARRAY)
            return "( " + s + ")";
        else if (to == W_HASHMAP)
            return "( " + s + ")";
        else if (to == W_FUNCTION)
            return "\n{\n" + s + "}\n";
    }

    function unwrap(string s) internal returns (string) {
        uint len = s.byteLength();
        return len > 2 ? s.substr(1, len - 2) : "";
    }

    /*function strrstr(string text, string pattern) internal returns (uint) {
        uint text_len = text.byteLength();
        uint pattern_len = pattern.byteLength();
        if (text_len < pattern_len)
            return 0;
        for (uint i = text_len - pattern_len; i > pattern_len; i--)
            if (text.substr(i, pattern_len) == pattern)
                return i + 1;
    }

    function str_context(string text, string pattern, string delimiter) internal returns (string) {
        uint q = stdio.strstr(text, pattern);
        if (q > 0) {
            uint d_len = delimiter.byteLength();
            string s_head = text.substr(0, q - 1);
            string s_tail = text.substr(q - 1 + pattern.byteLength());

            uint p = strrstr(s_head, delimiter);
            string s_before = p > 0 ? s_head.substr(p - 1 + d_len) : s_head;
            p = stdio.strstr(s_tail, delimiter);
            string s_after = p > 0 ? s_tail.substr(0, p - 1) : s_tail;
            return s_before + pattern + s_after;
        }
    }*/

}

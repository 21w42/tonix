pragma ton-solidity >= 0.51.0;

import "Commands.sol";
import "String.sol";

abstract contract SharedCommandInfo is Common, String {

    struct CmdInfoS {
        uint8 min_args;
        uint16 max_args;
        uint options;
    }
    mapping (uint8 => CmdInfoS) public _command_info;
    string[] public _command_names;

    function query_command_info() external view accept {
        SharedCommandInfo(msg.sender).update_command_info{value: 1 ton, flag: 1}(_command_names, _command_info);
    }

    function update_command_info(string[] command_names, mapping (uint8 => CmdInfoS) command_info) external accept {
        _command_names = command_names;
        _command_info = command_info;
    }

    function _command_index(string s) internal view returns (uint8) {
        uint len = _command_names.length;
        string[] commands;
        if (len > 1)
            commands = _command_names;
        else if (len == 1)
            commands = _split(_command_names[0], " ");

        for (uint8 i = 0; i < commands.length; i++)
            if (commands[i] == s)
                return i + 1;
    }

}

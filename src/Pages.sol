pragma ton-solidity >= 0.51.0;

import "Base.sol";

interface IPager {
    function add_page(Page page) external;
}

abstract contract Pages is Base {

    constructor(DeviceInfo dev, address source) Base (dev, source) public {
        _dev = dev;
        _source = source;
    }

    function _init() internal override {
    }

    function query_pages() external view accept {
        Page[] pages = _get_pages();
        for (Page page: pages)
            IPager(_source).add_page{value: 0.1 ton, flag: 1}(page);
    }

    function get_pages() external pure returns (Page[] pages) {
        return _get_pages();
    }

    function _get_pages() internal pure virtual returns (Page[] pages);

    function _add_page(string command, string purpose, string synopsis, string description, string option_list,
                        uint8 min_args, uint16 max_args, string[] option_descriptions) internal pure returns (Page page) {
        page = Page(command, purpose, synopsis, description, option_list, min_args, max_args, option_descriptions);
    }

}

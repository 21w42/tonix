MAKEFLAGS += --no-builtin-rules --warn-undefined-variables --no-print-directory
include Makefile.common

# Contracts
A:=AccessManager
B:=BlockDevice
D:=DataVolume
R:=StatusReader
I:=SessionManager
C:=FileManager
P:=PrintFormatted
M:=ManualPages
DM:=DeviceManager
AC:=AdminConsole
UC:=UserConsole
AL:=AssemblyLine
TB:=TextBlocks
STB:=StaticBackup
CF:=Configure
BFS:=BuildFileSys
PG_CMD:=PagesCommands
PG_SES:=PagesSession
PG_STAT:=PagesStatus
PG_AUX:=PagesUtility
PG_UA:=PagesAdmin
O:=BootManager

TA:=$A $D $R $B $I $C $M $P $(DM) $(PG_STAT) $(PG_CMD) $(PG_SES) $(PG_AUX) $(PG_UA) $(STB) $O $(CF) $(BFS)
INIT:=$(AL)
RKEYS:=$(KEY)/k1.keys
VAL0:=15
TST:=tests
VFS:=vfs
PROC:=$(VFS)/proc
STD:=std
DBG:=debug
ACC:=$(STD)/accounts

pid:=2

DIRS:=bin $(STD) $(VFS) $(PROC) $(ACC) $(DBG) $(patsubst %,$(STD)/%,$(TA))
BIL:=$(STD)/billion

PHONY += all install tools dirs cc caj trace tty tt genaddr init deploy balances compile clean
all: cc

install: dirs cc $(BIL)
	echo Tonix has been installed successfully
	$(TOC) config --url gql.custler.net --async_call=true

TOOLS_MAJOR_VERSION:=0.50
TOOLS_MINOR_VERSION:=0
TOOLS_VERSION:=$(TOOLS_MAJOR_VERSION).$(TOOLS_MINOR_VERSION)
TOOLS_ARCHIVE:=tools_$(TOOLS_MAJOR_VERSION)_$(UNAME_S).tar.gz
TOOLS_URL:=https\://github.com/tonlabs/TON-Solidity-Compiler/releases/download/$(TOOLS_VERSION)/$(TOOLS_ARCHIVE)
TOOLS_BIN:=$(LIB) $(SOLC) $(LINKER) $(TOC)
$(TOOLS_BIN):
	mkdir -p $(BIN)
	rm -f $(TOOLS_ARCHIVE)
	wget $(TOOLS_URL)
	tar -xzf $(TOOLS_ARCHIVE) -C $(BIN)

tools: $(TOOLS_BIN)
	$(foreach t,$(wordlist 2,4,$^),$t --version;)

npid?=2
dirs:
	mkdir -p $(DIRS)
	echo / > $(PROC)/cwd
	$(eval pid:=$(npid))
	mkdir -p $p
	cp $p/../cwd $p/
	mkdir -p $p/fd $p/fdinfo $p/map_files
	mkdir -p $p/fd/0 $p/fd/1 $p/fd/2

#clean:
#	for d in $(DIRS); do (cd "$$d" && rm -f *); done

DEPLOYED=$(patsubst %,$(BLD)/%.deployed,$(INIT))

cc: $(patsubst %,$(BLD)/%.tvc,$(INIT) $(TA))
	$(du) $^
si: $(patsubst %,$(BLD)/%.stateInit,$(INIT) $(TA))
	$(du) $^
caj: $(patsubst %,$(BLD)/%.abi.json,$(INIT) $(TA))
	$(du) $^
deploy: $(DEPLOYED)
	-cat $^
$(BLD)/%.code $(BLD)/%.abi.json: $(SRC)/%.sol
	$(SOLC) $< -o $(BLD)

$(BLD)/%.tvc: $(BLD)/%.code $(BLD)/%.abi.json
	$(LINKER) compile --lib $(LIB) $< -a $(word 2,$^) -o $@

$(BLD)/%.shift: $(BLD)/%.tvc $(BLD)/%.abi.json $(RKEYS)
	$(TOC) genaddr $< $(word 2,$^) --setkey $(word 3,$^) | grep "Raw address:" | sed 's/.* //g' >$@

$(BLD)/%.cargs:
	$(file >$@,{})

$(BLD)/%.deployed: $(BLD)/%.shift $(BLD)/%.tvc $(BLD)/%.abi.json $(RKEYS) $(BLD)/%.cargs
	$(call _pay,$(file < $<),$(VAL0))
	$(TOC) deploy $(word 2,$^) --abi $(word 3,$^) --sign $(word 4,$^) $(word 5,$^) >$@

$(BLD)/%.stateInit: $(BLD)/%.tvc
	$(BASE64) $< >$@

$(STD)/%.tvc:
	$(TOC) account -d $@ $($*_a)

p=$(PROC)/$(pid)

repo: $(DEPLOYED)
	$(foreach c,$^,printf "%s %s\n" $c `grep "deployed at address" $^ | cut -d ' ' -f 5`;)

define t-addr
$1_a=$$(shell grep -w $1 $2 | cut -f 1)
$1_n=$$(shell grep -w $1 etc/model | cut -f 1)
$$(eval $1_r0=$(TOC) -j run $$($1_a) --abi $(BLD)/$1.abi.json)
$$(eval $1_c0=$(TOC) call $$($1_a) --abi $(BLD)/$1.abi.json)
$1_ro=$$($1_r0) $$(@F) {} | jq -r '.out'
$1_r=$$($1_r0) $$(basename $$(@F)) $$< >$$@
$1_c=$$($1_c0) $$(basename $$(@F)) $$< >$$@
endef

#$(STD)/$1/upgrade.args: $(BLD)/$1.stateInit
#	$$(file >$$@,$$(call _args,c,$$(file <$$<)))

$(foreach c,$(TA),$(eval $(call t-addr,$c,etc/hosts)))
$(foreach c,$(INIT) $O,$(eval $(call t-addr,$c,etc/boot)))

etc/hosts:
	$(TOC) -j run $($O_a) --abi $(BLD)/$O.abi.json etc_hosts {} | jq -r '.out' | sed 's/ *$$//' >$@

etc/boot2:
	printf "%s\t%s\n" $($(AL)_a) $(AL) >$@
	printf "%s\t%s\n" `$($(AL)_r0) _boot_manager {} | jq -r '._boot_manager'` $O >>$@

deploy_boot_manager:
	$($(AL)_c0) deploy_boot_manager {}
update_code: $(BLD)/$(AL).stateInit
	$(TOC) call $($(AL)_a) --abi $(BLD)/$(AL).abi.json update_code '{"c":"$(file <$(word 1,$^))"}'

sync:
	$(TOC) config --async_call=false
async:
	$(TOC) config --async_call=true

$(STD)/%/boc:
	$(TOC) account $($*_a) -b $@

_jq=jq '.$1' <$@ >$p/$1
_jqr=jq -r '.$1' <$@ >$p/$1
_jqq=jq $2 '$3 .$1' <$@ >$p/$1

_jqa=$(foreach f,$1,$(call _jq,$f);) $(_p); $(_e)
_jqra=$(foreach f,$1,$(call _jqr,$f);)
_p=jq -j 'select(.out != null) .out' <$@
_jqsnn=$(call _jqq,$1,,select(.$1 != null))
_e=$(call _jqsnn,errors)
_f=grep "run failed" $@ && echo $(basename $(@F)) >$p/failed

npid?=3
process:
	$(eval pid:=$(npid))
	mkdir -p $p
	cp $p/../cwd $p/
	mkdir -p $p/fd $p/fdinfo $p/map_files
	mkdir -p $p/fd/0 $p/fd/1 $p/fd/2

g?=
ru: $p/$g.out
ca: $p/$g.res

$(BIL):
	echo /1000000000 >$@
$p/%.args:
	$(file >$@,{})

c0:
	@printf "Self-check started\n"
c1:
	$(TOC) -j account $($(AL)_a) >$(ACC)/$(AL).data
	@printf "Account\t\tSize\tBalance\tLast modified\n"
	$(call _print_status,$(AL))
c2: etc/boot
	$(TOC) -j account $($O_a) >$(ACC)/$O.data
	@printf "Account\t\tSize\tBalance\tLast modified\n"
	$(call _print_status,$O)
$(BLD)/images: $(patsubst %,$(BLD)/%.stateInit,$(INIT) $(TA))
	$($O_r0) _images {} | jq -j '._images[]' >$@
$(BLD)/images2: $(patsubst %,$(BLD)/%.stateInit,$(INIT) $(TA))
	$($(AL)_r0) _images {} | jq -j '._images[]' >$@
c7: etc/hosts
	-$($O_r0) etc_hosts {} | jq -r '.out' | diff - $^

_check_model=$(if $(shell jq -j 'select(.description == "$1") .model' <$2 | diff -q - $(BLD)/$1.stateInit),$(red)differs,$(green)matches)$x
_diff2=$(if $(shell jq -j 'select(.description == "$1") .model' <$2 | diff -q - $(BLD)/$1.stateInit),$(call _upg,$1),)
_upg=$(eval arg!=jq -sR '{n:$($1_n),c:.}' $(BLD)/$1.stateInit) $($(AL)_c0) upgrade_image '$(arg)';

c5: $(BLD)/images $(BLD)/images2
	$(foreach f,$(TA),printf '%s:\t%b\t%b\n' "$f" "$(call _check_model,$f,$(BLD)/images)" "$(call _check_model,$f,$(BLD)/images2)";)
	rm $^

uu: $(BLD)/images $(BLD)/images2
	$(foreach f,$(TA),printf '%s:\t%b\t%b\n' "$f" "$(call _check_model,$f,$(BLD)/images)" "$(call _check_model,$f,$(BLD)/images2)";)
	$(foreach f,$(TA),$(call _diff2,$f,$<))
	rm $^
_lbt=printf "%s\t" $1 && $($1_r0) _last_boot_time {} | jq -r '._last_boot_time' | $(date);
lbt:
	$(foreach f,$(TA),$(call _lbt,$f))
i0: $(BLD)/images
	$(foreach f,$(TA),$(call _diff2,$f,$<))
	rm $^

check_model_%: $(BLD)/%.stateInit
	-$($(AL)_r0) _images {} | jq -j '._images[] | select(.description == "$*") .model' | diff -q - $^
models:
	$($(AL)_ro)
roster system:
	$($(AL)_ro)
	$($O_ro)
dfs:
	$($O_r0) dfs '{"n":$n}' | jq -r '.out'
etc/devices:
	$($O_r0) get_system_devices {} | jq -r '.devices' >$@
multi:
	$($O_r0) multi {} | jq -r '.out'
get_system_devices:
	$($O_r0) get_system_devices {} | jq -r '.'

G:=config devices
$(BLD)/%.j: etc/%
	jq -Rs '{$*: .}' $^ >$@
gsi: $(patsubst %,$(BLD)/%.j,$G)
	$(eval args!=jq -rs 'add' $^)
	$(eval args2!=$($(CF)_r0) get_system_init '$(args)')
	$($(BFS)_r0) build_with_config '$(args2)'
	rm $^
gs:
	cp etc/config.sys etc/config
gm:
	cp etc/config.man etc/config

$(BLD)/manual.j: etc/manual
	jq -Rs '{config: .}' $^ >$@

fetch_command_names:
	$(eval args!=$($I_r0) fetch_command_names {})
	$($I_c0) set_command_names '$(args)'
get_command_info:
	$($M_r0) get_command_info {}
split:
	$(eval args!=$($I_r0) _command_names {} | jq '._command_names | .[]' | jq '{line: ., separator: " "}')
	$($(CF)_r0) split_line '$(args)'

build_init: $(patsubst %,$(BLD)/%.j,$G)
	$(eval args!=jq -rs 'add' $^)
	$(eval args2!=$($(CF)_r0) get_system_init '$(args)')
	$($(BFS)_r0) build_with_config '$(args2)' >$@
	rm $^

build_man: etc/config.man
build_sys: etc/config.sys

build_man build_sys:
	cp $< etc/config
	rm build_init
	make build_init

build_with_config: $(patsubst %,$(BLD)/%.j,$G)
	jq -rs 'add' $^ >$(BLD)/sys_iargs && $($(CF)_r0) get_system_init $(BLD)/sys_iargs >$(BLD)/system_init && $($(BFS)_r0) build_with_config $(BLD)/system_init >$@
	rm -f $(BLD)/sys_iargs $(BLD)/system_init $^

gid: etc/config
	jq -Rs '{config: .}' $(word 1,$^) >$(BLD)/config
	$($(CF)_r0) gen_init_data $(BLD)/config
	rm -f $(BLD)/config
di_%:
	$($(DM)_r0) _devices {} | jq -jr '._devices[] | select(.name == "$*") | map(.) | @tsv'
ck: c0 c1 models c2 c5
	@printf "Self-check completed\n"

############# System deploy routine #################
deploy_system:
	$($O_c0) deploy_system {}
	$($O_r0) get_system_devices {} | jq -r '.devices'
	mv etc/hosts etc/hosts.bak
	make etc/hosts
init_system:
	$($O_c0) init_system {}

set_manuals: etc/config.man
	cp $< etc/config
	make build_init
	$($O_c0) set_manuals build_init
	rm build_init

apply_image: etc/config.sys
	cp $< etc/config
	make build_init
	$($O_c0) apply_image build_init
	rm build_init

fetch_command_info:
	$(eval args!=$($M_r0) get_command_info {})
	$($M_c0) update_command_info '$(args)'
	$($I_c0) update_command_info '$(args)'

view_pages:
	$($M_r0) view_pages {}
t1:
	$($M_r0) transform_pages '{"start":0, "count":30}' >$@
t2:
	$($M_r0) transform_pages '{"start":30, "count":25}' >$@
t3:
	$($M_r0) transform_pages '{"start":55, "count":25}' >$@
t4:
	$($M_r0) transform_pages '{"start":80, "count":20}' >$@

process_pages:
	$($M_c0) process_pages t4
$p/login: $(STD)/login
	cp $< $@
$p/parse.args: $p/login $p/cwd $(STD)/s_input
	jq -sR '. | split("\n") | {i_login: .[0], i_cwd: .[1], s_input: .[2]}' $^ >$@
$p/parse.out: $p/parse.args
	$($I_r)
	$(call _jqa,session input arg_list input.command)
	$(call _jqra,cwd action ext_action)

$p/source: $p/parse.out
	jq -rj '.source' <$^ >$@
$p/target: $p/parse.out
	jq -rj '.target' <$^ >$@

$p/print_error_message.args: $p/input.command $p/errors
	jq -s '{command: .[0], errors: .[1]}' $^ >$@
$p/print_error_message.out: $p/print_error_message.args
	$($P_r)
	jq -j '.err' <$@
$p/read.out: $p/read.args
	$($B_r)
	$(call _jqa,)
$p/update_nodes.args: $p/session $p/ios
	jq -s '{session: .[0], ios: .[1]}' $^ >$@
$p/update_nodes.res: $p/update_nodes.args
	$($B_c)
$p/update_users.args: $p/session $p/ue
	jq -s '{session: .[0], ues: [.[1]]}' $^ >$@
$p/update_users.res: $p/update_users.args
	$($A_c)
$p/update_logins.args: $p/session $p/le
	jq -s '{session: .[0], le: .[1]}' $^ >$@
$p/update_logins.res: $p/update_logins.args
	$($A_c)
$p/dev_admin.args: $p/session $p/input $p/arg_list
	jq -s '{session: .[0], input: .[1], arg_list: .[2]}' $^ >$@
$p/dev_admin.res: $p/dev_admin.args
	$($(DM)_c)
n?=10
ct?=$O
$p/update_model.args: etc/models $(BLD)/$(TB).stateInit
	jq -sR '{n: $n, construction_cost: 5, description: "TextBlocks", block_size: 1024, n_blocks: 100, c:.}' $^ >$@
$p/update_model.res: $p/update_model.args
	$($(AL)_c)
$p/upgrade_image.args:
	jq -sR '{n:$n,c:.}' $(BLD)/$(ct).stateInit >$@
$p/upgrade_image.res: $p/upgrade_image.args
	$($(AL)_c)
$p/assemble_standard_device.args:
	jq -n '{n:$n}' >$@
$p/assemble_standard_device.res: $p/assemble_standard_device.args
	$($(AL)_c)
$p/assemble_custom_device.args:
	jq -n '{n:$n,block_size: 512,n_blocks: 400}' >$@
$p/assemble_custom_device.res: $p/assemble_custom_device.args
	$($(AL)_c)

$p/_roster.out:
	$($(AL)_r0) _roster {} >$@
$p/block_size: $p/_roster.out
	$(eval locations!=jq -r '._roster[].location' <$^)
	$(foreach f,$(locations),$(TOC) -j run $f --abi $(BLD)/$(TB).abi.json _blk_size {} | jq -r '._blk_size';)
tb?=2
f_in?=README.md
$p/chunks: $(f_in) $p/_roster.out
	$(eval location!=jq -r '._roster[$(tb)].location' <$(word 2,$^))
	$(eval block_size!=$(TOC) -j run $(location) --abi $(BLD)/$(TB).abi.json _blk_size {} | jq -r '._blk_size')
	$(eval n_blocks!=du --apparent-size $(word 1,$^))
	printf "LOC: %s BLK SIZE: %s BLOCKS: %s\n" $(location) $(block_size) $(n_blocks)
	mkdir -p $p/$(f_in)
	split -d -b $(block_size) $(word 1,$^) $p/$(f_in)/f.

_next_item="$(word 1,$1)"$(if $(word 2,$1),$(comma)$(call _next_item,$(wordlist 2,$(words $1),$1),))
_array_from_list=[$(if $(word 2,$1),$(call _next_item,$1),)]

$(STD)/$(AL)/updateImage_%.args: etc/model $(BLD)/%.stateInit
	grep -w $* $< | tr -d '\n' | jq -Rs '.| split("\t") | {n: .[0], construction_cost:.[1], description: .[2], block_size: .[3], n_blocks: .[4], c:"$(file <$(word 2,$^))"}' >$@

IMAGES:=$(patsubst %,$(STD)/$(AL)/updateImage_%.res,$(TA))

$(STD)/$(AL)/updateImage_%.res: $(STD)/$(AL)/updateImage_%.args
	$(TOC) call $($(AL)_a) --abi $(BLD)/$(AL).abi.json update_model $(word 1,$^)
$(STD)/$O/updateImage_%.res: $(STD)/$O/updateImage_%.args
	$(TOC) call $($O_a) --abi $(BLD)/$O.abi.json update_model $(word 1,$^)

upgrade: $(IMAGES)
	echo $^
ud2:
	$(eval arg!=jq -n '{act:3,actors:[2]}')
	$($O_c0) do_act '$(arg)'
init_x:
	$($O_c0) init_x '{"n":$n}'

dbfs:
	$(TOC) -j run $($(BFS)_a) --abi $(BLD)/$(BFS).abi.json dump_bfs {} | jq -r '.out'
ubfs: $(BLD)/$(BFS).stateInit
	$(TOC) call $($(BFS)_a) --abi $(BLD)/$(BFS).abi.json upgrade '{"c":"$(file <$(word 1,$^))"}'

mkdev:
	$($(AL)_c0) assemble_standard_device '{"n":$n}'

dd:
	$($B_r0) _blocks {}
	$($B_r0) _fd_table {}
	$($B_r0) _file_table {}
$p/text_in: $p/source
	cat $^ | xargs cat >$@
parts: $p/source
	cat $^ | xargs split -d -b 16000
parts_j.%: x0%
	jq -R '{text: .}' $^ >$@
$(BLD)/text_in.j: $p/text_in
	jq -Rs '{text: .}' $^ >$@

$(BLD)/target.j: $p/source
	jq -Rs '{path: .}' <$^ >$@
$(BLD)/session.j: $p/session
	jq '{session: .}' $^ >$@
$p/write_to_file.args: $(BLD)/session.j $(BLD)/target.j $(BLD)/text_in.j
	jq -s 'add' $^ >$@
$p/write_to_file.res: $p/write_to_file.args
	$($B_c)

_adds=$(shell jq -s 'add' $1 $2 $3)
_txarg=$(shell jq -R '{text: .}' $1)
_wrargs=$(call _adds,$(BLD)/session.j,$(BLD)/target.j,$(call _txarg,$1))

text.0%: x0%
	jq -Rs '{text: .}' $^ >$@
args_write.0%: $(BLD)/session.j $(BLD)/target.j text.0%
	jq -s 'add' $^ >$@
write.0%: args_write.0%
	$($B_c0) append_to_file $<
write.00: args_write.00
	$($B_c0) write_to_file $<

write_multi: $(wildcard args_write.0*)
	$($B_c0) write_to_file $<
	$(foreach a,$(wordlist 2,$(words $^),$^),$($B_c0) append_to_file $a;)
write_multi2: $(BLD)/session.j $(BLD)/target.j $p/source
	cat $(word 3,$^) | xargs split -d -b 15000
	$(eval args1!=$(call _wrargs,x01))
	echo $(args1)

$p/append_to_file.args: $(BLD)/session.j $(BLD)/target.j $(BLD)/text_in.j
	jq -s 'add' $^ >$@
$p/append_to_file.res: $p/append_to_file.args
	$($B_c)

$p/fstat.args: $p/session $p/input $p/arg_list
	jq -s '{session: .[0], input: .[1], arg_list: .[2]}' $^ >$@
$p/fstat.out: $p/fstat.args
	$($R_r)
	jq -j '.out' <$@

$p/dev_stat.args: $p/session $p/input $p/arg_list
	jq -s '{session: .[0], input: .[1], arg_list: .[2]}' $^ >$@
$p/dev_stat.out: $p/dev_stat.args
	$($(DM)_r)
	$(call _jqa,)

$p/account_info.args: $p/input
	jq -s '{input: .[0]}' $^ >$@
$p/account_info.out: $p/account_info.args
	$($(DM)_r)
	$(call _jqa,host_names addresses)

$p/file_op.args: $p/session $p/input $p/arg_list
	jq -s '{session: .[0], input: .[1], arg_list: .[2]}' $^ >$@
$p/file_op.out: $p/file_op.args
	$($C_r)
	$(call _jqa,ios)
	$(call _jqra,action)
$p/user_admin_op.args: $p/session $p/input
	jq -s '{session: .[0], input: .[1]}' $^ >$@
$p/user_admin_op.out: $p/user_admin_op.args
	$($A_r)
	$(call _jqa,ue)
	$(call _jqra,action)
$p/user_stats_op.args: $p/session $p/input
	jq -s '{session: .[0], input: .[1]}' $^ >$@
$p/user_stats_op.out: $p/user_stats_op.args
	$($A_r)
	$(call _jqra,action)
	jq -j '.out' <$@
$p/user_access_op.args: $p/session $p/input
	jq -s '{session: .[0], input: .[1]}' $^ >$@
$p/user_access_op.out: $p/user_access_op.args
	$($A_r)
	$(call _jqa,le)
	$(call _jqra,action)
	jq -j '.out' <$@
$p/process_command.args: $p/input
	jq -s '{input: .[0]}' $^ >$@
$p/process_command.out: $p/process_command.args
	$($P_r)
	jq -j '.out' <$@
$p/read_page.args: $p/input
	jq -s '{input: .[0]}' $^ >$@
$p/read_page.out: $p/read_page.args
	$($M_r)
	jq -j '.out' <$@
$p/format_text.args: $p/input $p/texts $p/arg_list
	jq -s '{input: .[0], texts: .[1], args: .[2]}' $^ >$@
$p/format_text.out: $p/format_text.args
	$($P_r)
	jq -j '.out' <$@
$p/process_text_files.args: $p/session $p/input $p/arg_list
	jq -s '{session: .[0], input: .[1], args: .[2]}' $^ >$@
$p/process_text_files.out: $p/process_text_files.args
	$($P_r)
	jq -j '.out' <$@
$p/read_indices.args: $p/arg_list
	jq -s '{args: .[0]}' $^ >$@
$p/read_indices.out: $p/read_indices.args
	$($B_r)
	jq '.texts' <$@ >$p/texts

$p/process_file_list.args: $p/session $p/input $p/dd_names_j $p/dd_indices_j
	jq -s '{session: .[0], input: .[1], names: .[2], indices: .[3]}' $^ >$@
$p/process_file_list.out: $p/process_file_list.args
	$($C_r)
	$(call _jqa,ios)

$p/fd/%/write_fd.args: $p/fd/%/start $p/fd/%/blocks
	jq -s '{fd: $*, start: .[0], blocks: .[1]}' $^ >$@
$p/fd/%/write_fd.res: $p/fd/%/write_fd.args
	$($B_c)
$p/next_write.args: $p/fdinfo/%
	jq -n '{fdi: .[$*]}' >$@
$p/fd/%/next_write.out: $p/next_write.args
	$($B_r)
	$(call _jqa,start count)

$p/nw_%:
	$($B_r0) next_write '{"fdi":$*}' >$@
	jq '.start' <$@ >$p/fd/$*/start
	jq '.count' <$@ >$p/fd/$*/count
	jq -Rs '[.]' $p/fd/$*/* >$p/fd/$*/blocks

$p/_proc.out: $p/_proc.args
	$($B_r)
	$(call _jqa,_proc)
$p/fd_table: $p/_proc.out
	jq -r '._proc["2"].fd_table' <$< >$@
$p/blk_size: $(STD)/$B/_dev.out
	jq -r '.[0].blk_size' <$< >$@
	$(foreach f,$(files),split -d --number=l/`grep ' $f ' $< | cut -d ' ' -f 3` $(SRC)/$f $f.;)
$p/fd_list: $p/fd_table
	jq -r 'keys | .[]' <$< >$@

fd_%: $p/op_table $p/fd_table
	jq -rS 'to_entries[] | select(.value.name=="$*") | .key' <$(word 2,$^)
nwr_%: $p/fd_table
	$(eval fdi!=jq -rS 'to_entries[] | select(.value.name=="$*") | .key' <$(word 1,$^))
	$($B_r0) next_write '{"pid":$(pid),"fdi":$(fdi)}'

%.boc:
	$(TOC) account $($*_a) -b $@
run_%: $(STD)/%/boc $(BLD)/%.abi.json
	$(TOC) -j run --boc $< --abi $(word 2,$^) $f {} | jq -r '.$l'
print: $(STD)/out $(STD)/err
	cat $<
	cat $(word 2,$^)
	rm -f $^

u_%: $(STD)/%/upgrade.args
	$($*_c0) upgrade $<
	rm -f $(STD)/$*/*
i_%:
	$($*_c0) init {}

pv_Dev=_proc _users
pv_Import=$(pv_Dev)
pv_Console=
pv_$(AC)=$(pv_Console)
pv_$(AL)=_images _roster _counter
pv_$O=$(pv_$(AL))
pv_$(UC)=$(pv_Console)
pv_$A=_users _groups _group_members _user_groups _login_defs_bool _login_defs_uint16 _login_defs_string _env_bool _env_uint16 _env_string _utmp _wtmp _ttys
pv_$C=$(pv_Dev)
pv_$R=$(pv_Dev)
pv_$I=$(pv_Dev) _command_info _command_names
pv_$B=$(pv_Dev) _file_table _blocks _fd_table _dev
pv_$D=
pv_$P=
pv_$M=_command_info _command_names
pv_$(STB)=_command_info _command_names
pv_$(TB)=_major_id _minor_id _blk_size _n_blocks _counter _blocks
pv_$(PG_CMD)=
pv_$(PG_SES)=
pv_$(PG_STAT)=
pv_$(PG_AUX)=
pv_$(PG_UA)=
pv_$(DM)=_devices _static_mounts _current_mounts
pv_$(CF)=
pv_$(BFS)=

_rb=$(TOC) -j run --boc $< --abi $(word 2,$^)
d3_%: $(STD)/%/boc $(BLD)/%.abi.json
	$(foreach r,$(pv_$*),$(_rb) $r {} | jq -r '.$r' >$(STD)/$*/$r.out;)

l?=1
dfs_%: $(STD)/%/boc $(BLD)/%.abi.json
	$(_rb) dump_fs '{"level":"$l"}' | jq -r '.value0'
	rm $<

_print_status=printf "%s\t" $1;\
	jq -j '."data(boc)"' <$(ACC)/$1.data | wc -m | tr '\n' '\t';\
	jq -j '.balance' <$(ACC)/$1.data | cat - $(BIL) | bc | tr '\n' '\t';\
	jq -j '.last_paid' <$(ACC)/$1.data | $(date)
$p/hosts: etc/hosts
	cut -f 2 <$< >$@
acc: $p/hosts
	rm -f $(ACC)/*
	$(eval hosts:=$(strip $(file <$(word 1,$^))))
	$(foreach h,$(hosts),$(TOC) -j account $($h_a) >$(ACC)/$h.data;)
	printf "Account\t\tSize\tBalance\tLast modified\n"
	$(foreach h,$(hosts),$(call _print_status,$h);)

tty tt: bin/xterm
	./$<
bin/xterm: $(SRC)/xterm.c
	gcc $< -o $@

TEST_DIRS:=$(wildcard $(TST)/*/*01.in)

vpath %.diff %.log %.golden %.tests $(TST)

$(TST)/%.diff: $(TST)/%.log $(TST)/%.golden
	-diff $^ >$@
	echo DIFF:
	cat $@
$(TST)/%.log: $(TST)/%.tests
	./bin/xterm <$< | tee $@
test:
	rm -f $(TST)/$t.diff $(TST)/$t.log
	make $(TST)/$t.diff

#include Disk.make

PHONY += FORCE
FORCE:

.PHONY: $(PHONY)

V?=
$(V).SILENT:

local -r _shell_hist_files=(
	"${HISTFILE:-"$HOME/.bash_history"}"
	"${HISTFILE:-"$HOME/.zsh_history"}"
	"$HOME/.local/share/fish/fish_history"
)

function config::shell::persist_history() {
	# Use workspace persisted history
	log::info "Persiting Gitpod shell histories to /workspace";
	local _workspace_persist_dir="/workspace/.persist";
	mkdir -p "$_workspace_persist_dir";
	local _hist;
	for _hist in "${_shell_hist_files[@]}"; do {
		mkdir -p "${_hist%/*}";
		_hist_name="${_hist##*/}";
		if test -e "$_workspace_persist_dir/$_hist_name"; then {
			log::info "Overwriting $_hist with workspace persisted history file";
			ln -srf "$_workspace_persist_dir/${_hist_name}" "$_hist";
		} else {
			touch "$_hist";
			cp "$_hist" "$_workspace_persist_dir/";
			ln -srf "$_workspace_persist_dir/${_hist_name}" "$_hist";
		} fi
		unset _hist_name;
	} done
}
function config::shell::hijack_gitpod_task_terminals() {
	# For debugging
	# trap 'read -p eval: && eval "$REPLY"' ERR EXIT SIGTERM SIGINT
	
	# Make gitpod task spawned terminals use fish
	if ! grep -q 'PROMPT_COMMAND=".*inject_tmux.*"' "$HOME/.bashrc" 2>/dev/null; then {
	log::info "Setting tmux as the interactive shell for Gitpod task terminals"
		function inject_tmux() {
			if test -v TMUX; then {
				return;
			} fi
			local tmux tmux_default_shell;
			function create_session() {
				tmux new-session -n home -ds "${tmux_first_session_name}"\; send-keys -t :${tmux_first_window_num} "cat $HOME/.dotfiles.log" Enter 2>/dev/null;
				tmux_default_shell="$(tmux display -p '#{default-shell}')";
				# local tmux_default_shell;
				# tmux_default_shell="$(tmux start-server\; display -p '#{default-shell}')";
			}
			function new_window() {
				exec tmux new-window -n "${WINDOW_NAME:-vs:${PWD##*/}}" -t main "$@";
			}
			function create_window() {
				if test ! -e "$tmux_init_lock" && test -z "$(tmux list-clients -t "$tmux_first_session_name")"; then {
					# create_window "$tmux_default_shell" -l;
					touch "$tmux_init_lock";
					# local tasks_count;
					# tasks_count="$(echo $GITPOD_TASKS | grep -Eo '(before|command|init)":"' | wc -l)"
					# if test "$tasks_count" -eq 1; then {
						new_window "$@" \; attach;
					# } else {
						# cmd "$@";
					# } fi
				} else {
					new_window "$@";
				} fi		
			}
			function get_task_term_name() {
				# Connect task terminals to tmux windows
				# Note: This is useless for now, however it works.
				local file_loc="/tmp/.gp_tasks_names";
				if test ! -e "$file_loc"; then {
					local term_id term_name task_state symbol ref;
					while IFS='|' read -r _ term_id term_name task_state _; do {
						if [[ "$term_id" =~ [0-9]+ ]]; then {
							for symbol in term_id term_name task_state; do {
								declare -n ref="$symbol";
								ref="${ref% }" && ref="${ref# }";
							} done
							if test "$task_state" == "running"; then {
								# (WINDOW_NAME="${term_name}" new_window gp tasks attach "$term_id")
								printf '%s\n' "$term_name" >> "$file_loc";
							} fi
							unset symbol ref;
						} fi
					} done < <(gp tasks list --no-color)
				} fi

				if test -e "$file_loc"; then {
					awk '{$1=$1;print;exit}' "$file_loc";
					sed -i '1d' "$file_loc";
				} fi
			}


			# For preventing the launch of VSCode process, we want to stay minimal and BLAZINGLY FAST LOL
			# By default it's off, to turn it on, set NO_VSCODE=true on https://gitpod.io/variables with */* as scope
			if test ! -e "$tmux_init_lock"; then {
				# local target="ssh://${GITPOD_WORKSPACE_ID}@${GITPOD_WORKSPACE_ID}.ssh.${GITPOD_WORKSPACE_CLUSTER_HOST}";
				"$HOME/.dotfiles/src/utils/vimpod.py" & disown
					(
						{ gp ports await 23000 && gp ports await 22000; } 1>/dev/null && gp preview "$(gp url 22000)" --external && {
							if test "${NO_VSCODE:-false}" == "true"; then {
								printf '%s\n' '#!/usr/bin/env sh' \
												'while sleep $(( 60 * 60 )); do continue; done' > /ide/bin/gitpod-code
								pkill -9 -f 'sh /ide/bin/gitpod-code';
							} fi
						}
					) &
				# printf '%s\n' '#!/usr/bin/env sh' \
				# 				'vimpod 2>&1' >/ide/bin/gitpod-code
						# "tmux_init_lock=$tmux_init_lock" \
						# "$(declare -f  new_window create_session create_task_terms_for_ssh_in_tmux)" \
				# create_session
			# 	# create_task_terms_for_ssh_in_tmux;
			# 	# declare -p BASH_SOURCE >/tmp/bs;
			# 	# if  [[ "${BASH_SOURCE[*]}" =~ /ide/startup.sh ]]; then {
			# 	# 	exit 0;
			# 	# } fi
			} fi

			touch "$tmux_init_lock"; # This skips auto focus & attachment to the TERMINAL view on VSCode, helpful for SSH_CONNECTION if vscode was not loaded.

			# The supervisor creates the task terminals, supervisor calls BASH from `/bin/bash` instead of the realpath `/usr/bin/bash`
			if [ "$BASH" == /bin/bash ] || [ "$PPID" == "$(pgrep -f "supervisor run" | head -n1)" ]; then {
				
				# Switch to tmux on SSH.
				if test -v SSH_CONNECTION; then {
					if test "${NO_VSCODE:-false}" == "true"; then {
						pkill -9 vimpod || :;
					} fi
					# Tmux window sizing conflicts happen as by default it inherits the smallest client sizes (which is usually the terminal TAB on VSCode)
					# There are two things we can do, either detach all the connected clients. (tmux detach -t main)
					# or tell tmux to allways use the largest size, which can confuse some people sometimes.
					# I'll go with the second option for now
					# (for i in {1..5}; do sleep 2 && tmux set-window-option -g -t main window-size largest; done) & disown
					create_session;
					exec tmux set-window-option -g -t "${tmux_first_session_name}" window-size largest\; attach -t :${tmux_first_window_num};
				} fi

				create_session;

				termout=/tmp/.termout.$$
				if test ! -v bash_ran_once; then {
					exec > >(tee -a "$termout") 2>&1;
				} fi
				# if test -v bash_ran_once; then {
				# 	can_switch=true;
				# } fi

				local stdin;
				IFS= read -t0.01 -u0 -r -d '' stdin;
				if test -n "$stdin"; then {
					if test "${DEBUG_DOTFILES:-false}" == true; then {
						declare -p stdin
						read -rp running
						set -x
					} fi
					stdin=$(printf '%q' "$stdin")
					WINDOW_NAME="$(get_task_term_name)" create_window bash -c "trap 'exec $tmux_default_shell -l' EXIT; less -FXR $termout | cat; printf '%s\n' $stdin; eval $stdin;";
					# (eval "$stdin")
					# exit; 
					# can_switch=true;
				} else {
					if test "${DEBUG_DOTFILES:-false}" == true; then {
						read -rp exiting;
					} fi
					exit;
				} fi

				# if test -v can_switch; then {
					# if test "${DEBUG_DOTFILES:-false}" == true; then {
						# read -p waiting;
					# } fi
				# 	create_window "less -FXR $termout | cat; exec $tmux_default_shell -l";
				# } else {
					bash_ran_once=true;
				# } fi
			# } fi

			} else {
				unset ${FUNCNAME[0]} && PROMPT_COMMAND="${PROMPT_COMMAND/${FUNCNAME[0]};/}";
			} fi


		}

		# Entry point, very important!!!
		printf '%s\n' "tmux_first_session_name=$tmux_first_session_name" \
						"tmux_first_window_num=$tmux_first_window_num" \
						"tmux_init_lock=$tmux_init_lock" \
						"$(declare -f inject_tmux)" 'PROMPT_COMMAND="inject_tmux;$PROMPT_COMMAND"' >> "$HOME/.bashrc";
		# sudo cp -a "$source_dir/src/utils/vimpod.py" /usr/bin/vimpod # Sad noises :')
		
	} fi
}

function config::shell::fish::append_hist_from_gitpod_tasks() { 
	# Append .gitpod.yml:tasks hist to fish_hist
	log::info "Appending .gitpod.yml:tasks shell histories to fish_history";
	while read -r _command; do {
		if test -n "$_command"; then {
			printf '\055 cmd: %s\n  when: %s\n' "$_command" "$(date +%s)" >> "${_shell_hist_files[2]}";
		} fi 
	} done < <(sed "s/\r//g" /workspace/.gitpod/cmd-* 2>/dev/null || :)
}

function config::shell::vscode::set_tmux_as_default_shell() {
	log::info "Setting the integrated tmux shell for VScode as default";
	local file json_data;
	local ms_vscode_server_dir="$HOME/.vscode-server";
	local ms_vscode_server_settings="$ms_vscode_server_dir/data/Machine/settings.json";
	json_data="$(cat <<-'JSON' | sed "s|main|${tmux_first_session_name}|g"
		{
			"terminal.integrated.profiles.linux": {
				"tmuxshell": {
					"path": "bash",
					"args": [
						"-c",
						"tmux new-session -ds main 2>/dev/null || :; if cpids=$(tmux list-clients -t main -F '#{client_pid}'); then for cpid in $cpids; do [ $(ps -o ppid= -p $cpid)x == ${PPID}x ] && exec tmux new-window -n \"vs:${PWD##*/}\" -t main; done; fi; exec tmux attach -t main; "
					]
				}
			},
			"terminal.integrated.defaultProfile.linux": "tmuxshell"
		}
	JSON
	)"

	printf '%s\n' "$json_data" | vscode::add_settings;
	# For vscode desktop
	# TIME=2 wait::for_file_existence "$ms_vscode_server_dir";
	printf '%s\n' "$json_data" | SETTINGS_TARGET="$ms_vscode_server_settings" vscode::add_settings;
}
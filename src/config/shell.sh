local -r _shell_hist_files=(
    "$HOME/.bash_history"
    "$HOME/.zsh_history"
    "$HOME/.local/share/fish/fish_history"
)

function shell::persist_history() {
    # Use workspace persisted history
    log::info "Persiting Gitpod shell histories to /workspace";
    local _workspace_persist_dir="/workspace/.persist";
    mkdir -p "$_workspace_persist_dir";
    local _hist;
    for _hist in "${_shell_hist_files[@]}"; do {
        mkdir -p "${_hist%/*}";
        _hist_name="${_hist##*/}";
        if test -e "$_workspace_persist_dir/$_hist_name"; then {
            log::warn "Overwriting $_hist with workspace persisted history file";
            ln -srf "$_workspace_persist_dir/${_hist_name}" "$_hist";
        } else {
            touch "$_hist";
            cp "$_hist" "$_workspace_persist_dir/";
            ln -srf "$_workspace_persist_dir/${_hist_name}" "$_hist";
        } fi
        unset _hist_name;
    } done
}
function shell::hijack_gitpod_task_terminals() {
    # Make gitpod task spawned terminals use fish
    log::info "Setting tmux as the interactive shell for Gitpod task terminals"
    if ! grep -q 'PROMPT_COMMAND=".*tmux new-session -As main"' "$HOME/.bashrc"; then {
        # The supervisor creates the task terminals, supervisor calls BASH from `/bin/bash` instead of the realpath `/usr/bin/bash`
		function inject_tmux() {
			function create_window() {
				(cd $HOME && tmux new-session -n home -ds main 2> /dev/null || :);
				exec tmux new-window -n "vs:${PWD##*/}" -t main "$@";
			}
			if [ "$BASH" == /bin/bash ]; then {
				if test ! -v TMUX; then {
					create_window "$BASH" -l \; attach;
				} fi
				if test -v bash_ran_once && [ "$PPID" == "$(pgrep -f "supervisor run" | head -n1)" ]; then {
					can_switch=true;
				} fi

				# local hist_cmd="history -a /dev/stdout";
				# if test -z "$($hist_cmd)"; then {
				# 	can_switch=true;
				# 	echo emp
				# } fi

				if test -v can_switch; then {
					# read -n 1 -rs -p "$(printf '\n\n>>> Press any key for switching to tmux')";
					# local tmux_init_lock=/tmp/.tmux.init;
					# tmux_default_shell="$(tmux display -p '#{default-shell}')";

					# if test -e "$tmux_init_lock"; then {
	                    # create_window "$tmux_default_shell" -l;
						create_window;
						# exit 0;
					# } else {
						# touch "$tmux_init_lock";
						# create_window "$tmux_default_shell" -l \; attach;
					# } fi
				} else {
					bash_ran_once=true;
				} fi
			} else {
				unset ${FUNCNAME[0]} && PROMPT_COMMAND="${PROMPT_COMMAND/${FUNCNAME[0]};/}";
			} fi

		}
		printf '%s\n' "$(declare -f inject_tmux)" 'PROMPT_COMMAND="inject_tmux;$PROMPT_COMMAND"' >> "$HOME/.bashrc";
    } fi
}

function fish::append_hist_from_gitpod_tasks() { 
    # Append .gitpod.yml:tasks hist to fish_hist
    log::info "Appending .gitpod.yml:tasks shell histories to fish_history";
    while read -r _command; do {
        if test -n "$_command"; then {
            printf '\055 cmd: %s\n  when: %s\n' "$_command" "$(date +%s)" >> "${_shell_hist_files[2]}";
        } fi 
    } done < <(sed "s/\r//g" /workspace/.gitpod/cmd-* 2>/dev/null || :)
}


function bash::gitpod_start_tmux_on_start() {
	local file="$HOME/.bashrc.d/10-tmux";
	printf '(cd $HOME && tmux new-session -n home -ds main 2>/dev/null || :) & rm %s\n' "$file" > "$file";
}
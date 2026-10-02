[[ $- == *i* ]] || return

PS1='\[\e[1m\]\A \W\$ \[\e[0m\]'

. /usr/share/bash-completion/bash_completion
eval "$(fzf --bash)"
export FZF_DEFAULT_OPTS='--style minimal --layout reverse --info inline --exact'
_fzf_preview='
	case $(file --mime-type -b {}) in
		image/*) chafa -f symbols -s "${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}" {} ;;
		inode/directory) ls -la --color=always {} ;;
		text/*|*/xml|*/json|*/javascript) sed -n "1,120p" {} ;;
		*) file {} ;;
	esac
'
export FZF_CTRL_T_OPTS="--preview '$_fzf_preview' --preview-window right,50%,noborder"
export FZF_COMPLETION_OPTS="--preview '$_fzf_preview' --preview-window right,50%,noborder"
export FZF_ALT_C_OPTS="--preview 'ls -la --color=always {}' --preview-window right,50%,noborder"
export FZF_CTRL_R_OPTS="--bind 'ctrl-y:execute-silent(printf %s {2..} | wl-copy)+abort'"
unset _fzf_preview

set -o noclobber

export EDITOR=vis VISUAL=vis

alias ld='ls -Alh --color=auto'
alias gl='git clone --depth=1'

lfcd() {
	cd "$(command lf -print-last-dir "$@")" || return
}
alias lf=lfcd

ni() {
	if [[ -n ${WAYLAND_DISPLAY:-} || -n ${DISPLAY:-} ]]; then
		printf 'Graphical session already running.\n' >&2
		return 1
	fi
	export XDG_RUNTIME_DIR="/tmp/xdg-runtime-$UID"
	install -d -m 700 "$XDG_RUNTIME_DIR" || return
	dbus-run-session niri --session
}

HISTSIZE=100000
HISTFILESIZE=200000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend lithist

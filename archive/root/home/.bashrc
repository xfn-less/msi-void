[[ $- == *i* ]] || return

PS1='\[\e[1m\]\A \W\$ \[\e[0m\]'

. /usr/share/bash-completion/bash_completion
eval "$(fzf --bash)"
export FZF_DEFAULT_OPTS='--style minimal --layout reverse --info inline --exact'
export FZF_CTRL_T_OPTS="--preview '
	case \$(file --mime-type -b {}) in
		image/*) chafa -f symbols -s \"\${FZF_PREVIEW_COLUMNS}x\${FZF_PREVIEW_LINES}\" {} ;;
		inode/directory) ls -la --color=always {} ;;
		text/*|*/xml|*/json|*/javascript) sed -n \"1,120p\" {} ;;
		*) file {} ;;
	esac
' --preview-window right,50%,noborder"
export FZF_ALT_C_OPTS="--preview 'ls -la --color=always {}' --preview-window right,50%,noborder"
export FZF_DEFAULT_COMMAND='find . -type f -not -path "*/.git/*"'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

set -o noclobber

export EDITOR=vis VISUAL=vis

alias ld='ls -Alh --color=auto'
alias gl='git clone --depth=1'

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


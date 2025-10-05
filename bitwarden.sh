#!/bin/bash

bw-switch() {
	VAULT_PATH="$HOME/.config/Bitwarden CLI"
	if [[ "$#" -ge 1 && -f "$VAULT_PATH/$1/data.json" ]]; then
		ln -sf "$VAULT_PATH/$1/data.json" "$VAULT_PATH/data.json"
		echo "Vault switched to \"$1\"."
	else
		echo "Error. Could not find vault \"$1\"."
	fi
}

bw-search() {
	# processing CLI arguments
	for arg in "$@"; do
		if [[ $next_arg_type == "session" ]]; then
			session=$arg
			next_arg_type=""
			continue
		fi

		case $arg in
			"--notes" | "-n")
				print_note="true"
				;;
			"--show" | "-S")
				print_sensitive="true"
				;;
			"--interactive" | "-i")
				interactive="true"
				;;
			"--session")
				next_arg_type="session"
				;;
			*)
				if [[ ${arg:0:1} == "-" ]]; then
					for (( i=1; i<${#arg}; i++ )); do
						char=${arg:$i:1}
						case $char in
							"n")
								print_note="true"
								;;
							"S")
								print_sensitive="true"
								;;
							"i")
								interactive="true"
								;;
							*)
								echo "Unknown option: \"$char\""
						esac;
					done
				elif [[ -n $search_term ]]; then
					echo "Unknown argument \"$arg\"".
					exit
				else
					search_term="$search_term $arg"
				fi
				;;
		esac
	done

	# handling CLI errors
	if [[ ! $next_arg_type == "" ]]; then
		echo "Missing argument for [$next_arg_type]"
		exit
	fi
	if [[ ! -n $search_term ]]; then
		echo "Missing a search term."
		exit
	fi

	# getting login/session
	if [[ ! -n $session ]]; then
		echo -n "Password: "
		read -s password
		echo -e -n "\r\033[K"
		session=$(bw unlock --raw $password)
	fi
	if [[ ! -n $session ]]; then
		exit
	fi

	# getting output
	output=$(bw list items --session $session --search "$search_term" --pretty)
	if [[ $output == "[]" ]]; then
		echo "No results found."
		exit
	fi

	# processing value substitution flags
	if [[ -n $print_note ]]; then print_note="\n\tNotes: \\(.notes)"; fi

	# Parsing JSON output & printing
	for (( i=0; i<$(jq length <<< $output); i++)); do
		if [[ $(jq ".[$i] | has(\"login\")" <<< $output) == "true" ]]; then
			type=login
		elif [[ $(jq ".[$i] | has(\"card\")" <<< $output) == "true" ]]; then
			type=card
		fi

		# deal with printing sensitive info
		sensitive_str="[hidden]";
		if [[ i -eq 0 ]]; then
			sensitive_str="[copied to clipboard]"
			if [[ $type == login ]]; then 
				sensitive=$(jq .[0].login.password <<< $output)
			else
				sensitive=$(jq .[0].card.number <<< $output)
			fi
			echo -n "${sensitive:1:-1}" | xclip -selection clipboard
		fi
		if [[ -n $print_sensitive ]]; 
			then if [[ $type == login ]];
				then sensitive_str="\\(.login.password)"; 
				else sensitive_str="\\(.[\$k])"
			fi
		fi

		# deal with printing notes/fields
		if [[ -n $print_note ]]; then 
			note_str='"", "\(.fields | .[] |
					"\t\(.name): \(.value | gsub("\n";"; "))")", "",
					  "\t\(if .notes != null then "Notes: \(.notes | gsub("\n";"; "))" end)"'
		fi
		
		jq ".[$i]" <<< $output
		jq -r ".[$i].name | ." <<< $output
		if [[ $type == login ]]; then
			jq -r ".[$i] | \"\tUsername: \(.login.username)\n\" + 
						   \"\tPassword: ${sensitive_str}\"" <<< $output
			jq -r ".[$i] | ${note_str}" <<< $output
		elif [[ $type == card ]]; then
			jq -r ".[$i].card | keys_unsorted[] as \$k | 
				if \"\(\$k)\" == \"number\" 
				then \"\tnumber: $sensitive_str\"
				else \"\t\(\$k): \(.[\$k])\" end" <<< $output
			jq -r ".[$i] | ${note_str}" <<< $output
		else
			echo "Unknown type (login, card, etc.)"
		fi

	done
	echo "here, exited"


#	if [[ $(jq length <<< $output) > 1 ]]; then
#		filter=".[] | select(.name != null) | \"\\(.name)\\n\\tUsername: \\(.login.username)\\n\\tPassword: ${print_sensitive}${print_note}\""
#		jq -r "$filter" <<< $output
#	else
#		if [[ "$print_sensitive" == "[hidden]" ]]; then
#			print_sensitive="[copied to clipboard]"
#		fi
#		filter=".[0] | \"\\(.name)\\n\\tUsername: \\(.login.username)\\n\\tPassword: ${print_sensitive}${print_note}\""
#		jq -r "$filter" <<< $output
#		password=$(jq .[0].login.password <<< $output)
#		echo -n "${password:1:-1}" | xclip -selection clipboard
#	fi
#
	if [[ -n $interactive ]]; then
		while true; do
			echo -n ">> "
			read input

			if [[ $input == "exit" || $input == "quit" ]]; then
				exit
			fi
		done
	fi



}

cmd=$(basename "$0")
case "$cmd" in
    "bw-switch")
		bw-switch "${@:1}"
        ;;
    "bw-search")
		bw-search "${@:1}"
        ;;
    *)
        echo "Unknown command: $cmd"
        echo "Available commands: bw-switch, bw-search"
        exit 1
        ;;
esac

#!/bin/bash
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <path_to_the_input_PCD_dir> <path_to_the_output_PCD_dir>"
    echo $1
    echo $2
    exit 1
fi

info="[\033[0;32mINFO \033[0m]:"
warning="[\033[0;33mWARN \033[0m]:"
error="[\033[0;31mERROR\033[0m]:"

bind '"\e[A": history-search-backward' 2>/dev/null
bind '"\e[B": history-search-forward' 2>/dev/null
history -r script_history

function select_option {
  local initial_selection=${1:-0}
  shift
  local options=("$@")
  ESC=$(printf "\033")
  cursor_blink_on() { printf "%s[?25h" "$ESC"; }
  cursor_blink_off() { printf "%s[?25l" "$ESC"; }
  cursor_to() { printf "%s[%s;%sH" "$ESC" "$1" "${2:-1}"; }
  print_option() { printf "           %s " "$1"; }
  print_selected() { printf "         %s[4;36m〉%s%s[0m" "$ESC" "$1" "$ESC"; }
  print_fixed() { printf "         %s[32m✔ %s%s[0m" "$ESC" "$1" "$ESC"; }
  get_cursor_row() {
    # shellcheck disable=SC2034
    IFS=';' read -srdR -p $'\E[6n' ROW COL
    echo "${ROW#*[}"
  }
  key_input() {
    read -rs -n3 key 2>/dev/null >&2
    if [[ $key = ${ESC}[A ]]; then echo up; fi
    if [[ $key = ${ESC}[B ]]; then echo down; fi
    if [[ $key = "" ]]; then echo enter; fi
  }

  for opt in "${options[@]}"; do printf "\n"; done

  local lastrow
  lastrow=$(get_cursor_row)

  local startrow=$((lastrow - ${#options[@]}))

  trap "cursor_blink_on; stty echo; printf '\n'; exit" 2
  cursor_blink_off

  local selected=$initial_selection
  while true; do
    local idx=0
    for opt in "${options[@]}"; do
      cursor_to $((startrow + idx))
      if [ $idx -eq "$selected" ]; then
        print_selected "$opt"
      else
        print_option "$opt"
      fi
      ((idx++))
    done

    case $(key_input) in
    enter) break ;;
    up)
      ((selected--))
      if [ $selected -lt 0 ]; then selected=$((${#options[@]} - 1)); fi
      ;;
    down)
      ((selected++))
      if [ $selected -ge ${#options[@]} ]; then selected=0; fi
      ;;
    esac
  done

  cursor_to $((startrow + selected))
  print_fixed "${options[selected]}"

  cursor_to "$lastrow"
  cursor_blink_on

  return "$selected"
}

function get_cursor_position {
    exec < /dev/tty
    local oldstty
    oldstty=$(stty -g)
    stty raw -echo min 0
    echo -en "\033[6n" > /dev/tty
    IFS=';' read -r -d R -a pos
    stty "$oldstty"
    local row=$((${pos[0]:2} - 1))
    local col=$((pos[1] - 1))
    echo "$row $col"
}

function move_cursor {
    local row=$1
    local col=$2
    echo -en "\e[${row};${col}H\e[J"
}

script_dir="/mapfourmer/"
home_dir="/home/$(ls /home/ --ignore=fstab --ignore=user)/"
declare -A quality_ltta=(
  ["0"]="0"
  ["1"]="2"
  ["2"]="5"
  ["3"]="10"
  ["4"]="10"
)

echo -e "$info MapFourmerへようこそ。設定ウィザードを開始します。"

# Input Path
input_path=$1

if [ ! -f "${input_path}" ] && [ ! -d "${input_path}" ]; then
    echo -e "Error: Could not find the input folder ${input_path}"
    exit 1
else
    echo "Input folder: ${input_path}"
fi

# Output Path
output_path=$2
if [ ! -d "$output_path" ]; then
    echo -e "The output folder ${output_path} was not found. Creating one..."
    mkdir -p "$output_path"
else
    echo "Output folder: ${output_path}"
fi

# Format
# Remove dynamic points only
format="noise"

# Ceckpoint
declare -a artifact_names=()
ls ""${script_dir}"/artifacts/"
for file in "${script_dir}/artifacts/"*.pth.enc; do
  artifact_names+=("$(basename "$file" .pth.enc)")
  echo "${file}"
echo 
done

echo -e "$info 使用するモデルを上矢印と下矢印キーを使用して選択してください。"
select_option 0 "${artifact_names[@]}"
choice=$?

model_path="$script_dir/artifacts/${artifact_names[$choice]}.pth.enc"
if [ ! -f "$model_path" ]; then
  echo -e "$error モデルファイルが見つかりませんでした: $model_path"
  echo -e "$error support@map4.jpまでご連絡ください"
  exit 1
fi

config_path="${script_dir}/artifacts/${artifact_names[$choice]}.yaml"

# Quality (TTA)
# echo -e "$info 出力の品質を選択してください。品質が高いほど処理に時間がかかりメモリ使用量が増加します。"
# select_option 2 "最低品質（最高速）" "低品質（高速）" "バランス" "高品質（低速）" "最高品質（最低速）"
# echo -e "${info} Select processing quality"
# select_option 2 "最低品質（最高速）" "低品質（高速）" "バランス" "高品質（低速）" "最高品質（最低速）"
# choice=$?
choice="2"  # Balance
ltta=${quality_ltta[$choice]}

epoch=$(date +%s)
export M4E_EPOCH="${epoch}"
export M4E_PID="$$"

trap 'echo; echo "処理が中断もしくは終了しました。"; $script_dir/devel/lib/map4_util/license_release; exit 130' SIGINT SIGTERM


# shellcheck disable=SC1091
. /mapfourmer/.venv/bin/activate

export LD_LIBRARY_PATH="/mapfourmer/devel/lib:${LD_LIBRARY_PATH}"

# Run
echo -e "${info} 設定が完了しました。 処理を開始します。"

OMP_NUM_THREADS=4 "${script_dir}/.venv/bin/python3" "${script_dir}/src/inference.py" \
  "${input_path}" \
  "${output_path}" \
  "${config_path}" \
  "${model_path}" \
  --grid-size 30 \
  --num-local-tta "${ltta}" \
  --batch-size 1 \
  --format "${format}" \
  --use-adaptive-voxel-size

result=$?

"${script_dir}/devel/lib/map4_util/license_release"

if [ $result -eq 0 ]; then
  echo -e "${info} 処理が正常に完了しました。"
else
  echo -e "${error} エラーが発生し処理が正常に完了しませんでした。"
  echo -e "${error} 問題が解決されない場合はエラー内容とともにsupport@map4.jpまでご連絡ください。"
fi
echo -e "${info} 別のファイルに対して処理を行いたい場合は、'bash mapfourmer.sh'をこのまま実行してください。"

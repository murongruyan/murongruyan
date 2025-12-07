#!/system/bin/sh
TeamS=${0%/*}
BASEDIR="$(dirname $(readlink -f "$0"))"
# Default root ator coolapk@int萌新很新
MNT="/mnt/vendor/"
MagiskVers="$(magisk -V)"
function mount_replacing(){
	if [ "$MagiskVers" -lt 26000 ]; then
        mount --bind "$TeamS$1" "$1"
	else
		mount -o bind "$TeamS$1" "$1"
	fi
}

function mount_bind(){
	if [ "$MagiskVers" -lt 26000 ]; then
        mount --bind "$1" "$2"
	else
		mount -o bind "$1" "$2"
	fi
}

function my_mount_recursive(){
    for file in "$TeamS/$1"/*; do
        if [ -f "$file" ]; then
            # If the file is a regular file, mount it in the corresponding subfile in root
            sub_file=$(basename "$file")
            chmod --reference="$MNT$1/$sub_file" "$file" 
            chown --reference="$MNT$1/$sub_file" "$file" 
            mount -o bind "$file" "$MNT$1/$sub_file"
            # Preserve the original file's permissions and ownership
        elif [ -d "$file" ]; then
            # If the file is a directory, recurse into it and mount all files inside
            sub_dir=$(basename "$file")
            my_mount_recursive "$1/$sub_dir"
        fi
    done
}

map_files() {
  local module="$1"
  local dir="$2"
  find "$module/$dir" -type f 2>/dev/null | while read -r src
  do
	local dst="${src#$module/}"
	  if [[ -f "$dst" ]]
	  then
		if [[ "$dst" == "my_*" ]]
		then
		  mount --bind "$src" "/mnt/vendor/$dst"
		else
		  mount --bind "$src" "/$dst"
		fi
	  fi
  done
}

map_files ${0%/*} odm
map_files ${0%/*} my_product
map_files ${0%/*} system

# Example usage:
# my_mount my_product
# my_mount odm

MNT="/" #从根目录挂载（默认从/mnt/vendor/挂载）
mount_replacing /data/oplus/os/bpm/sys_elsa_config_list.xml

#禁用温控
stop oppo_theias
stop thermal_mnt_hal_service
stop orms-hal-1-0
stop fuelgauged
stop smartcharging
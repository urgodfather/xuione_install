#!/usr/bin/env bash
set -euo pipefail

### Helpers ###
is_root() {
  [[ $EUID -eq 0 ]]
}

detect_os() {
  . /etc/os-release
  echo "$ID $VERSION_ID"
}

prompt_yesno() {
  # $1 = prompt, default no
  read -rp "$1 [y/N] " ans
  [[ $ans =~ ^[Yy] ]]
}

remove_xtream_ui() {
  echo "Removing Xtream UI (Xtream Codes)…"
  systemctl stop mysql.service 2>/dev/null || true
  apt purge -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-* || true
  rm -rf /etc/mysql /var/lib/mysql /var/log/mysql
  apt autoremove -y
  apt autoclean -y

  pkill -u xtreamcodes 2>/dev/null || true
  pkill -f 'iptv_xtream_codes' 2>/dev/null || true
  chattr -i /home/xtreamcodes/iptv_xtream_codes/GeoLite2.mmdb 2>/dev/null || true
  umount -f /home/xtreamcodes/iptv_xtream_codes/{streams,tmp} 2>/dev/null || true
  rm -rf /home/xtreamcodes/iptv_xtream_codes/{streams,tmp}
  sed -i '/xtreamcodes/d' /etc/fstab /etc/crontab /etc/sudoers 2>/dev/null || true
  deluser --remove-home xtreamcodes 2>/dev/null || true
  groupdel xtreamcodes 2>/dev/null || true
  chown root:root -R /home/xtreamcodes 2>/dev/null || true
  chmod -R 0644 /home/xtreamcodes 2>/dev/null || true

  rm -f /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock /var/lib/dpkg/lock
  apt-get remove -y libcurl3 || true
}

remove_streamcreed() {
  echo "Removing StreamCreed panel…"
  systemctl stop mariadb.service 2>/dev/null || true
  apt purge -y mariadb-server || true
  rm -rf /etc/mysql /var/lib/mysql /var/log/mysql
  apt autoremove -y
  apt autoclean -y

  pkill -u streamcreed 2>/dev/null || true
  pkill -f 'streamcreed' 2>/dev/null || true
  umount -f /home/streamcreed/{streams,tmp} 2>/dev/null || true
  rm -rf /home/streamcreed/{streams,tmp}
  sed -i '/streamcreed/d' /etc/fstab /etc/crontab /etc/sudoers 2>/dev/null || true
  deluser --remove-home streamcreed 2>/dev/null || true
  groupdel streamcreed 2>/dev/null || true
  chown root:root -R /home/streamcreed 2>/dev/null || true
  chmod -R 0644 /home/streamcreed 2>/dev/null || true
}

install_mariadb_105() {
  if dpkg -l | grep -qE 'mariadb-server\s.*10\.5'; then
    echo "MariaDB 10.5 is already installed."
    return
  fi
  echo "Installing MariaDB 10.5…"
  apt update
  apt install -y software-properties-common dirmngr wget
  wget -qO- https://mariadb.org/mariadb_release_signing_key.asc | apt-key add -
  add-apt-repository \
    "deb [arch=amd64,arm64,ppc64el] http://mirror.lstn.net/mariadb/repo/10.5/ubuntu focal main"
  apt update
  apt install -y \
    mariadb-server=1:10.5.*+maria~ubu2004 \
    mariadb-client=1:10.5.*+maria~ubu2004
  apt-mark hold 'maria*'
  echo "MariaDB 10.5 installed and held."
}

download_and_run() {
  local mode="$1" version="$2"
  local zipname="XUI_${version}.zip"
  local url="https://update.xui.one/${zipname}"
  echo "Downloading XUI ${version} (${mode})…"
  wget -q "$url" -O "/tmp/${zipname}"
  cd /tmp
  apt update
  apt install -y zip unzip
  unzip -o "$zipname"
  if [[ $mode == "install" ]]; then
    ./install
  else
    ./update
  fi
}

### Main ###
if ! is_root; then
  echo "This script must be run as root."; exit 1
fi

echo "Detected OS: $(detect_os)"
if ! grep -qE 'Ubuntu (18\.04|20\.04)' /etc/os-release; then
  echo "⚠️  This script is tested on Ubuntu 18.04/20.04 only—proceed at your own risk."
  prompt_yesno "Continue anyway?" || exit 1
fi

# 1) Remove old panels
if [[ -d /home/xtreamcodes/iptv_xtream_codes || $(systemctl list-units --all | grep -q xtream; echo $?) -eq 0 ]]; then
  if prompt_yesno "Detected Xtream UI—remove it now?"; then
    remove_xtream_ui
  fi
fi

if [[ -d /home/streamcreed || $(systemctl list-units --all | grep -q streamcreed; echo $?) -eq 0 ]]; then
  if prompt_yesno "Detected StreamCreed—remove it now?"; then
    remove_streamcreed
  fi
fi

# 2) MariaDB 10.5
install_mariadb_105

# 3) Choose fresh install vs update existing XUI
echo
echo "Choose XUI action:"
echo "  1) Fresh install"
echo "  2) Update existing XUI"
read -rp "Select [1-2]: " action
if [[ $action == "1" ]]; then
  mode="install"
elif [[ $action == "2" ]]; then
  mode="update"
else
  echo "Invalid choice."; exit 1
fi

# 4) Choose version
echo
echo "Available XUI versions:"
echo "  a) 1.5.5 (stable)"
echo "  b) 1.5.12 (beta)"
echo "  c) 1.5.13 (latest official)"
read -rp "Select [a-c]: " ver
case $ver in
  a) version="1.5.5" ;;
  b) version="1.5.12" ;;
  c) version="1.5.13" ;;
  *) echo "Invalid choice."; exit 1 ;;
esac

# 5) Download & run
download_and_run "$mode" "$version"

# 6) Apply XUI.ONE patch
echo "Applying XUI.ONE patch..."
bash <(wget -qO- https://github.com/xuione/XUIPatch/raw/refs/heads/main/patch.sh)

# 7) Done
cat <<EOF

✅ XUI ${version} ${mode^^} complete with patch!

Next steps:
  • In the XUI UI → Servers → Update/reinstall your Load Balancers.
  • In the top-right corner click the Lock icon → Regenerate Security Key.
  • Manage your panel:
      /home/xui/service {stop|start}
      /home/xui/status            # show DB status
      /home/xui/tools            # list maintenance tools

Enjoy your fresh XUI setup!
EOF

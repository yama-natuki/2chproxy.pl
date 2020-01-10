#!/bin/bash
#
# 2chroxy.pl install script.
#

# install.shの引数---------------------
# 第1引数でスクリプトのインストール場所を指定する
# 省略した場合は $HOME/bin にインストールされる
bin_dir="${1:-$HOME/bin}"

# 第2引数でJDimの場所を指定する
# 省略した場合はPATHからjdimを探し、見つからなければインストールは実行しない
jdim_path="${2:-$(command -v jdim 2>/dev/null)}"

# 設定-----------------------------
# JDimの場所
JD="$jdim_path"
# jd.confの場所
# install.shは環境変数 JDIM_CACHE によるキャッシュディレクトリの変更を考慮しない
if test "$JD" = "/snap/bin/jdim" ; then
  # Snapパッケージ
  jd_conf="$HOME/snap/jdim/common/.cache/jdim/jd.conf"
elif "$JD" --version 2>/dev/null | grep -F 'disable-compat-cache-dir' >/dev/null 2>&1 ; then
  # JDのキャッシュディレクトリが無効化されている場合
  jd_conf="${XDG_CACHE_HOME:-$HOME/.cache}/jdim/jd.conf"
elif test -d "$HOME/.jd" ; then
  # JDのキャッシュディレクトリが残っている場合
  jd_conf="$HOME/.jd/jd.conf"
else
  # JDimのデフォルト
  jd_conf="${XDG_CACHE_HOME:-$HOME/.cache}/jdim/jd.conf"
fi

# JDの設定
# 板一覧を取得するサーバ
url_bbsmenu="http://menu.5ch.net/bbsmenu.html"
# 2chのクッキー：HAPを保存する＝はい
use_cookie_hap="1"
# 2chのクッキー：HAP
cookie_hap="__cfduid=d;yuki=akari"
# BBSPINKのクッキー
cookie_hap_bbspink="__cfduid=d;yuki=akari"

#----------------------------------



pgrep jdim > /dev/null && {
    echo "JDimを終了させてから実行してください。" >&2
    exit 1;
}

echo "Find jd.conf... $jd_conf"
if [ ! -f "$jd_conf" ]; then
    echo "$jd_conf が見付かりません。一度JDimを起動し作成しておいてください。" >&2
    exit 1;
fi

echo "Find executable file... $JD"
if [ ! -x "$JD" ]; then
    echo "${JD:-jdim} が存在しないか実行属性がありません。\n 実行ファイルを確認してください。" >&2
    exit 1;
fi

# perl library check.
declare -a module=("HTTP::Daemon" "LWP::UserAgent" "LWP::Protocol::https")

for i in ${module[@]}; do
    perl -M$i -e '' >& /dev/null
    if [ $? -ne 0 ]; then
        echo "perl module [$i] is not found." >&2
        exit 1;
    fi
done

# Set source and target directories
base_dir=$( cd "$( dirname "$0" )" && pwd )

test -d "$bin_dir" || mkdir --parents "$bin_dir"

echo "Copying 2chproxy.pl to ${bin_dir}"
dat_directory="$(dirname $jd_conf)/"
cat ${base_dir}/2chproxy.pl | \
  sed -e "s|DAT_DIRECTORY => \"[^\"]\+|DAT_DIRECTORY => \"${dat_directory}|" \
      > ${bin_dir}/2chproxy.pl
chmod +x ${bin_dir}/2chproxy.pl

echo "Copying jd.sh to ${bin_dir}"
cat ${base_dir}/jd.sh | \
    sed -e "s|^PROXY=.*$|PROXY=${bin_dir}/2chproxy\.pl|" \
        -e "s|^JD=.*$|JD=${JD}|" \
        > ${bin_dir}/jd.sh
chmod +x  ${bin_dir}/jd.sh

desktop="$HOME/.local/share/applications"
echo "Copying jdim.desktop to ${desktop}"
test -d $desktop || mkdir --parents $desktop
cat ${base_dir}/jd.desktop | \
    sed -e "s|^Exec=.*$|Exec=${bin_dir}\/jd.sh|" \
        -e "s|^Icon=jd$|Icon=jdim|" \
        -e "s|JD|JDim|" \
        -e "s|gtkmm2|gtkmm|" \
        > ${desktop}/jdim.desktop

#
# change jd.conf
#

# proxy port
PORT=$(cat ${base_dir}/2chproxy.pl | sed -n '/^  LISTEN_PORT.*/s/^  LISTEN_PORT => \([0-9]\+\).*/\1/p')

# proxy
use_proxy_for2ch="1"
proxy_for2ch="127.0.0.1"
proxy_port_for2ch=$PORT
use_proxy_for2ch_w="1"
proxy_for2ch_w="127.0.0.1"
proxy_port_for2ch_w=$PORT

# jd.conf backup.
echo "Backup to jd.conf"
cp -p $jd_conf{,.$(date "+%Y%m%d_%H%M%S")}

echo "replace jd.conf"
sed -e "s|^url_bbsmenu = .*$|url_bbsmenu = ${url_bbsmenu}|" \
    -e "s|^use_cookie_hap = .*$|use_cookie_hap = ${use_cookie_hap}|" \
    -e "s|^cookie_hap = .*$|cookie_hap = ${cookie_hap}|" \
    -e "s|^cookie_hap_bbspink = .*$|cookie_hap_bbspink = ${cookie_hap_bbspink}|" \
    -e "s|^use_proxy_for2ch = .*$|use_proxy_for2ch = ${use_proxy_for2ch}|" \
    -e "s|^proxy_for2ch = .*$|proxy_for2ch = ${proxy_for2ch}|" \
    -e "s|^proxy_port_for2ch = .*$|proxy_port_for2ch = ${proxy_port_for2ch}|" \
    -e "s|^use_proxy_for2ch_w.*$|use_proxy_for2ch_w = ${use_proxy_for2ch_w}|" \
    -e "s|^proxy_for2ch_w.*$|proxy_for2ch_w = ${proxy_for2ch_w}|" \
    -e "s|^proxy_port_for2ch_w.*$|proxy_port_for2ch_w = ${proxy_port_for2ch_w}|" \
    -i $jd_conf

echo "done."

#END

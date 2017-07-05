#!/bin/bash
#
# 2chroxy.pl install script.
#

# 設定-----------------------------
#JDの場所
JD="/usr/bin/jd"
# jd.confの場所
jd_conf="$HOME/.jd/jd.conf"

# JDの設定
# 板一覧を取得するサーバ
url_bbsmenu="http://kita.jikkyo.org/cbm/cbm.cgi/2r.pr.m0.sc.op/-all/bbsmenu.html"
# 2chのクッキー：HAPを保存する＝はい
use_cookie_hap="1"
# 2chのクッキー：HAP
cookie_hap="__cfduid=d;yuki=akari"
# BBSPINKのクッキー
cookie_hap_bbspink="__cfduid=d;yuki=akari"

#----------------------------------



pgrep jd > /dev/null && {
    echo "JDを終了させてから実行してください。";
    exit 1;
}

# Set source and target directories
base_dir=$( cd "$( dirname "$0" )" && pwd )

# if an argument is given it is used to select wich 2chproxy.pl to install
bin_dir="${$1:-$HOME/bin}"
test -d "$bin_dir" || mkdir --parent "$bindir"
 
echo "Copying 2chproxy.pl to ${bin_dir}"
cp -p ${base_dir}/2chproxy.pl $bin_dir

echo "Copying jd.sh to ${bin_dir}"
cat ${base_dir}/jd.sh | \
    sed -e "s|^PROXY=.*$|PROXY=${bin_dir}/2chproxy\.pl|" \
        -e "s|^JD=.*$|JD=${JD}|" \
        > ${bin_dir}/jd.sh
chmod +x  ${bin_dir}/jd.sh

echo "Copying jd.desktop..."
cat ${base_dir}/jd.desktop | \
    sed -e "s|^Exec=.*$|Exec=${bin_dir}\/jd.sh|" \
        > $HOME/.local/share/applications/jd.desktop 

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

#END

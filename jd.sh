#!/bin/sh
# last updated : 2015/03/16 01:20:30 JST
#
# 2chproxy.pl を起動してからJDを起動する。
#

# 2chproxy.plの場所をフルpathで書く。
PROXY="$HOME/bin/2chproxy.pl"
# JDの場所
JD="/usr/bin/jd"

if [  -f ${PROXY} ]; then
	if [ ! -x ${PROXY} ]; then
		echo "${PROXY} に実行属性が付与されていません。chmod +x して付与してください。";
		exit 1;
	fi
else
	echo "${PROXY} が見つかりません。\n pathかファイル名が正しいか確認してください。";
	exit 1;
fi

pgrep 2chproxy.pl
if [ $? -ne 0 ]; then
	${PROXY} --daemon;
	$JD;
	${PROXY} --kill;
else
	$JD;
	${PROXY} --kill;
fi

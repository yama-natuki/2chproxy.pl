

# 導入方法

ubuntu14.04LTS の場合。

## 事前に必要なパッケージを導入。

`  sudo apt-get install git  libhttp-daemon-perl liblwp-protocol-https-perl`

## インストール

`  git clone https://github.com/yama-natuki/2chproxy.pl.git`

　次回からは、

`  git pull`

するだけで更新できます。

# 設定

 2chproxy.pl 内を参照。

# 起動方法

　_2chproxy.pl_ というディレクトリが作成されるので、その中の **2chproxy.pl** を直接起動させるか、_~/bin/_ 等にコピーして使う。

## jd.2h

　同梱の **jd.sh** はJDを起動する前に **2chproxy.pl** を起動させるシェルスクリプト。

　使う場合は、

```
    PROXY="$HOME/bin/2chproxy.pl"  
    JD="/usr/bin/jd"
```

の二つを自分の環境に合わせて変更。

## jd.desktop

　同梱の **jd.desktop** はGUIからJDを起動する前に **2chproxy.pl** を起動させるデスクトップエントリ。

　使う場合は、**jd.desktop** ファイルを _~/.local/share/applications/_ に コピーする。

　**2chproxy.pl** を入れた場所を変更した場合は、

`  Exec=$HOME/2chproxy.pl/jd.sh`

の行を変更する。


# JDの設定

　設定→ネットワーク→プロキシ で2ch読み込み用のみ設定する。書き込みはプロキシを使用しない。

　また場合によっては高度な設定で 2chにアクセスするときのエージェント名や、2chのクッキーを見直す。

2chproxy.pl
===============================

2chproxy.plとは？
-------------------------------

　APIでスレ取得ができない2ch専用ブラウザのためのhtml→dat変換フロントエンドです。  
　proxyとして動作し、JD、navi2ch、rep2 等に対応しています。


# 導入方法

ubuntu14.04LTS の場合。

## 事前に必要なパッケージを導入。

　すでに必要なパッケージが入っていれば実行する必要はありません。

`  sudo apt-get install git  libhttp-daemon-perl liblwp-protocol-https-perl libyaml-tiny-perl`

## ダウンロード

`  git clone https://github.com/yama-natuki/2chproxy.pl.git`

　次回からは作成されたディレクトリ、 _2chproxy.pl/_ に移動し、

`  git pull`

すれば更新されます。

# インストール

　作成されたディレクトリ、 _2chproxy.pl/_ に移動し、

`   ./install.sh`

すれば自動でインストールからJDの設定までしてくれます。

あとはリログし、JDのアイコンをクリックするだけです。

# 設定

 2chproxy.pl 内を参照。

## コンフィグファイルで設定する

　設定を別ファイルに記述しておく事がでru。別にしておけば 2chproxy.pl を更新するたびに
設定をやり直さなくて済む。

　記述の仕方は [YAML形式](https://ja.wikipedia.org/wiki/YAML) で記述していく。
同梱の sample.yml を参照。

　使用する場合は、

`  ./2chproxy.pl --config ~/.2chproxy.yml`

などとして設定ファイルの場所を指定して起動。

------------------------------------

# 手動で弄る場合

## 起動方法

　_2chproxy.pl_ というディレクトリが作成されるので、その中の **2chproxy.pl** を直接起動させるか、_~/bin/_ 等にコピーして使う。

## jd.sh

　同梱の **jd.sh** はJDを起動する前に **2chproxy.pl** を起動させるシェルスクリプト。

　使う場合は、

```
    PROXY="$HOME/bin/2chproxy.pl"  
    JD="/usr/bin/jd"
```

の二つを自分の環境に合わせて変更。

## jd.desktop

　同梱の **jd.desktop** はGUIからJDを起動する前に **2chproxy.pl** を起動させるデスクトップエントリ。

　使う場合は、**jd.desktop** ファイルを _~/.local/share/applications/_ に コピーし、

`  Exec=$HOME/2chproxy.pl/jd.sh`

の行を、 _jd.sh_ の絶対pathに変更。


## JDの設定

　設定→ネットワーク→プロキシ で2ch読み込み用のみ設定する。書き込みはプロキシを使用しない。

　また場合によっては高度な設定で 2chにアクセスするときのエージェント名や、2chのクッキーを見直す。


# 変更点

　細かい変更点は [コミットログ](https://github.com/yama-natuki/2chproxy.pl/commits/master) を参照。

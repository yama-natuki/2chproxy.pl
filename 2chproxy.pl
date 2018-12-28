#!/usr/bin/perl

#Copyright (C) 2015 ◆okL.s3zZY5iC
#Released under the MIT license
#http://opensource.org/licenses/mit-license.php

#v1.2.1からの変更点
# URL置換でダブらないように修正
# スレタイ検索でもURLを置換するようにした
#
#v1.2からの変更点
# 余計な物までURLの置換対象になっていたので修正
# beアイコンのurl書き換え部分の修正
# ENABLE_2CH_TO_nCHの設定値が増えた関係で
#   v1.2.1では"4"がv1.2での"3"相当のものになった
# きっと増えているバグ

#注意事項
#0. LinuxのJD(要は俺環)で動くことを想定して作っているので他の環境で動くかは分かりません
#1. Webスクレイピングを有効にすると本来鯖から取得できるdatと
#   整合性が取れなくなる恐れがあります
#2. 専ブラで"200 OK"ではなく"416 Requested Range Not Satisfiable."が出た場合は
#   datファイルの整合性が取れていないことによるエラーの可能性が高いです
#   特に、WebスクレイピングのON/OFFを繰り返して使用した場合に起こりやすいです
#   JDではスレ一覧の右クリックメニューのその他->スレ情報を消さずに再取得を行えばOK
#3. 設定を変える際は原則として下のPROXY_CONFIG内の変数をいじってください
#4. 設定の変更を適用する場合はプロクシの再起動が必要です
#5. Windowsで使う場合はActive Perlではなくcygwin+perlを使う方が良いかもしれません
#   現状で問題なく動いているなら変える必要はないと思います
#6. 一部オプションにはdatを目に見える形で書き換える機能があるので
#   テンプレを用いたスレ立てには注意して下さい
#7. きっとエラーは発生します
#8. 自己責任で使ってください
#
#専用スレがあるようなのでスレが見られる人は
#これに関する話題はそちらを使うといいかもしれません
# http://hayabusa6.2ch.net/test/read.cgi/linux/1429072845/l50

#use
use strict;

use utf8;
use POSIX;

use Encode 'encode';
use File::Basename qw(dirname basename);
use Getopt::Long qw(:config posix_default no_ignore_case gnu_compat);
use HTTP::Daemon;
use IO::Compress::Gzip qw(gzip $GzipError);
use LWP::UserAgent;
use Scalar::Util qw(blessed);
use URI;
use threads;
use threads::shared;
use Thread::Semaphore;

#定数の宣言(実質的なコンフィグファイル)
my $PROXY_CONFIG  = {
  PROXY_CONFIG_FILE => '',                            #コンフィグファイル
  DEDICATED_BROWSER => "JD",                          #使用している専ブラの名前
                                                      #スクレイピング時にDAT_DIRECTORYと合わせてローカルのdatへアクセスするのに必要
  DAT_DIRECTORY => "$ENV{HOME}/.jd/",                 #datファイルが置いてあるディレクトリ、最後の/はつけた方が良い
                                                      #ローカルにあるdatへアクセスするのに必要
  LISTEN_HOST => "localhost",                         #listenするホスト、ipv4に強制するなら"127.0.0.1"
  LISTEN_PORT => 8080,                                #listenするポート
  FORWARD_PROXY => '',                                #上位プロクシがあれば"http://host:port/"みたいに書く
  MAXIMUM_CONNECTIONS => 20,                          #最大同時接続数
  USER_AGENT => 'Mozilla/5.0 (X11; Linux x86_64; rv:55.0) Gecko/20100101 Firefox/55.0',
                                                      #UA偽装
  ENABLE_WEB_SCRAPING => 1,                           #datへのアクセスの際にWEBスクレイピングを有効にする
                                                      #datへの直アクセスが禁止されない限りは有効にしない方がいい
                                                      #0で無効、1で有効
  ENABLE_PARTIAL_CONTENT => 1,                        #ENABLE_WEB_SCRAPINGが有効な状態で
                                                      #datへのアクセスにRnageヘッダーが含まれていた場合に
                                                      #206で応答するようにする
                                                      #0で無効、1で有効
  ENABLE_MEMORY_CACHE => 1,                           #メモリ上でdatの取得したサイズ、最新のレスの番号と内容をキャッシュする
                                                      #極稀に整合性がとれなくなる
                                                      #0で無効、1で有効
  DISABLE_GZIP_COMPRESS => 1,                         #過去ログ(.dat.gz)へのアクセスをスクレイピングした際も
                                                      #圧縮せずにテキストのまま返す
                                                      #0で無効、1で有効
  TIMEOUT => 9,                                       #接続のタイムアウト値
                                                      #専ブラのタイムアウト値より小さい値にした方が良い
  DISABLE_TE_HEADER => 1,                             #If-Modified-Sinceヘッダーのない要求がプロクシに来た場合に
                                                      #TEヘッダーが付加されるのを止めるかどうか
                                                      #0で無効、1で有効
  ALLOW_CONNECT_METHOD => 1,                          #CONNECTメソッドを有効にする、動くには動くが
                                                      #しっかりした処理ではないので通信内容が壊れるかもしれない
                                                      #0で無効、1で有効
  TCP_CONNECTION_BUFFER => 8192,                      #CONNECT中のバッファーの最大bytes数
  ENABLE_IMG_TO_LINK => 0,                            #   *dat書き換え*
                                                      #お絵かきをimgタグからurlへ変換する
                                                      #0で無効、1で有効
  ENABLE_REPLACE_HTTPS_LINK => 0,                     #   *dat書き換え*
                                                      #httpsな2ch/bbspinkのリンクをhttpに変換する
                                                      #専ブラの置換機能で弄れる場合はそちらを使う方が良い
                                                      #0で無効、1で有効
  ENABLE_2CH_TO_nCH => 1,                             #   *dat書き換え*
                                                      #nch.net<->2ch.netの変換を行う
                                                      #0で無効
                                                      #1で2ch.netへのアクセスをnch.netへ変換
                                                      #2で1に加えて2ch->nchへのリンク書き換え
                                                      #3で1に加えてbbsmenuのみnch->2chへのリンク書き換え
                                                      #4で3に加えてdatもnch->2chへのリンク書き換え
                                                      # - 専ブラが5ch.netの板を認識できる
                                                      #   - 専ブラの置換機能で2chのリンクを5chのに置換する/置換の必要なし ->  1
                                                      #   - 専ブラに置換機能が無い/使用しない(串側で置換する)             ->  2
                                                      # - 認識できない
                                                      #   - 専ブラの置換機能で5chのリンクを2chのに置換する                ->  3
                                                      #   - 専ブラに置換機能が無い/使用しない(串側で置換する)             ->  4
  ENABLE_REPLACE_BE_AUTH_RESPONSE => 1,               #Beの認証時に302が返ってきたら200に置き換える
                                                      #0で無効、1で有効
  THREAD_TITLE_SEARCH_URL => '',                      #スレ検索に使うURL
                                                      #スレ検索でのURLの置換が必要な場合はURLを設定する
                                                      #URLを指定しなければ無効
                                                      #ENABLE_2CH_TO_nCHが1 or 2なら2ch->5ch
                                                      #                   3 or 4なら5ch->2ch
  KEEP_COOKIE => 1,                                   #このプロクシで*.2ch.net、*.bbspink.comのcookieを保持するかどうかのフラグ
                                                      #0で無効、1で有効
  UNIQ_COOKIE => 0,                                   #KEEP_COOKIEが有効になっている状態で
                                                      #書き込み毎にcookieを変えたい場合はこれを有効にする
                                                      #0で無効、1で有効
  HANDLED_COOKIES => [qw(__cfduid yuki PREN)],        #KEEP_COOKIEが有効な時にプロクシで保持するクッキー
  DAT_URL => '^https?://([\w]+)(\.\d+ch\.net|\.bbspink\.com)(:[\d]+)?/([\w]+)/(?:dat|kako/\d+(?:/\d+)?)/([\d]+(?:-[\d]+)?)\.dat(\.gz)?$',  #datへのアクセスかを判定する正規表現
  NULL_DEVICE => '/dev/null',                         #nullデバイスの場所
  PID_FILE_NAME => "/tmp/2chproxy.pid",               #pidが書かれたファイル、2重起動禁止にも用いている
  LOG_FILE_NAME => "/tmp/2chproxy.log",               #ログファイル
  NULL_DEVICE_WIN32 => 'nul',                         #nullデバイスの場所(Windows)
  PID_FILE_NAME_WIN32 => dirname($0)."/2chproxy.pid", #pidが書かれたファイル、2重起動禁止にも用いている(Windows)
  LOG_FILE_NAME_WIN32 => dirname($0)."/2chproxy.log", #ログファイル(Windows)
  LOG_LEVEL => 5,                                     #ログ出力の閾値
  #以下WEBスクレイピングの際の正規表現
  HTML2DAT_TITLE_REGEX => '<title>(.*?)(\x0d?\x0a?)</title>',             #タイトル抽出
  #                       1.レス番                        2.目欄           3.名前/ハッシュ                4.1.日付                       4.2.SE1                       4.3.ID     4.4 <0000>                               5.BE1           6.BE2          7.本文
  HTML2DAT_REGEX => '<dt>(\d+)\s[^<]*<(?:a href="mailto:([^"]+)"|font[^>]*)><b>(.*?)</b></(?:a|font)>.((?:[^<]+?)(?:\s*<a href="?http[^">]*"?[^>]*>[^<]*</a>)?(?:\s*(?:[^<]+?(?:(?:<\d+>)+[^<]*)?))?)?\s*(?:<a\s[^>]*be\(([^)]*)\)[^>]*>\?([^<]+)</a>)?<dd>([^\n]+)',
  HTML2DAT_REGEX2 => '<(?:div|span) class="number">(\d+)[^<]*</(?:div|span)><(?:div|span) class="name"><b>(?:<a href="mailto:([^"]+)">((?:(?!</a>).)*)</a>|(?:<font[^>]*>)?((?:(?!<\w+ class="date">).)*?)(?:</font>)?)</b></(?:div|span)><(?:div|span) class="date">((?:(?!(?:<div class="message">|<dd class="thread_in">)).)*?)</\w+>(?:<(?:div|span) class="be\s[^"]+"><a href="https?://be.\d+ch.net/user/(\d+)"[^>]*>\?([^>]+)</a>)?(?:|</div>|</span></div>)(?:<div class="message">|</dt><dd class="thread_in">)((?:(?!</(?:div|dd)>).)*)</(?:div|dd)>',
  #WEBスクレイピングの細かい部分の正規表現は下の方
};

#ログ出力用、こっちは弄らないでね
use constant {
  LOG_DEBUG => 7,
  LOG_INFO => 6,
  LOG_NOTICE => 5,
  LOG_WARN => 4,
  LOG_ERR => 3,
};

#グローバル変数の宣言
my $log_level = $PROXY_CONFIG->{LOG_LEVEL};
my $null_device_name;
my $pid_file_name;
my $log_file_name;
my $charcode;
my ($is_daemon, $kill_process, $print_verbose);
my $dedicated_browser;
my $dat_directory;
my $enable_guess_encoding;
my %cookie :shared;
my %mem_cache :shared;
my $semaphore;
my $tcp_connection_buffer;
my @handlers;
my $version_number = '1.2.2';

#
sub config_error_check() {
  if ($PROXY_CONFIG->{DAT_DIRECTORY} !~ m|/$|) {
    $PROXY_CONFIG->{DAT_DIRECTORY}  .= '/';
  }
  if ($PROXY_CONFIG->{LISTEN_PORT} <= 0 || $PROXY_CONFIG->{LISTEN_PORT} > 65535) {
    $PROXY_CONFIG->{LISTEN_PORT}  = 8080;
  }
  if ($PROXY_CONFIG->{MAXIMUM_CONNECTIONS} <= 0) {
    $PROXY_CONFIG->{MAXIMUM_CONNECTIONS}  = 1;
  }
  if ($PROXY_CONFIG->{TIMEOUT} < 0) {
    $PROXY_CONFIG->{TIMEOUT}  = 0;
  }
  if ($PROXY_CONFIG->{TCP_CONNECTION_BUFFER} < 1024) {
    $PROXY_CONFIG->{TCP_CONNECTION_BUFFER}  = 1024;
  }
}

#グローバル変数の初期化
sub initialize_global_var() {
  &config_error_check();
  $log_level = $PROXY_CONFIG->{LOG_LEVEL};
  #ログレベルの変更
  if ($print_verbose) {
    $log_level += $print_verbose;
  }
  $null_device_name = ($^O !~ m|MSWin32|i) ? $PROXY_CONFIG->{NULL_DEVICE} : $PROXY_CONFIG->{NULL_DEVICE_WIN32};
  $pid_file_name = ($^O !~ m|MSWin32|i) ? $PROXY_CONFIG->{PID_FILE_NAME} : $PROXY_CONFIG->{PID_FILE_NAME_WIN32};
  $log_file_name = ($^O !~ m|MSWin32|i) ? $PROXY_CONFIG->{LOG_FILE_NAME} : $PROXY_CONFIG->{LOG_FILE_NAME_WIN32};

  $charcode  = "UTF-8";
  #とりあえずWindowsだけcp932で出力
  if ($^O =~ m/MSWin32/) {
    $charcode = "cp932";
  }

  $dedicated_browser  = $PROXY_CONFIG->{DEDICATED_BROWSER};
  $dat_directory  = $PROXY_CONFIG->{DAT_DIRECTORY};

  #nch<->2chのリンクの書き換えを行う為
  #https->httpのリンク書き換えを利用する
  if ($PROXY_CONFIG->{ENABLE_2CH_TO_nCH} == 2 || $PROXY_CONFIG->{ENABLE_2CH_TO_nCH} == 4) {
    $PROXY_CONFIG->{ENABLE_REPLACE_HTTPS_LINK} = 1;
  }

  #Encode::Guessによる文字コード判別が可能であれば有効にする
  eval {
    require Encode::Guess;
  };
  if (!$@) {
    import Encode::Guess qw(cp932 utf8 euc-jp ascii);
    $enable_guess_encoding  = 1;
  }

  $tcp_connection_buffer  = $PROXY_CONFIG->{TCP_CONNECTION_BUFFER};
  #TEヘッダーの付加をしないように設定する
  if ($PROXY_CONFIG->{DISABLE_TE_HEADER}) {
    push(@LWP::Protocol::http::EXTRA_SOCK_OPTS, SendTE => 0);
  }
  else {
    push(@LWP::Protocol::http::EXTRA_SOCK_OPTS, SendTE => 1);
  }
  #keep-alive時に
  push(@LWP::Protocol::http::EXTRA_SOCK_OPTS, KeepAlive => 1);
  push(@LWP::Protocol::http::EXTRA_SOCK_OPTS, HTTPVersion => '1.1');
  push(@LWP::Protocol::http::EXTRA_SOCK_OPTS, PeerHTTPVersion => '1.1');
  #セマフォの設定
  $semaphore  = Thread::Semaphore->new($PROXY_CONFIG->{MAXIMUM_CONNECTIONS});
}

sub print_log() {
  my $level  = shift;
  my $tag = shift;
  my @args = @_;
  my ($package, $file, $line) = caller;

  if ($level <= $log_level) {
    if (!defined($charcode)) {
      print @args;
    }
    else {
      print Encode::encode($charcode, '['.threads->tid().'|'.$line.'] '.$tag.": ".join("", @args));
    }
  }
}

#help
sub help() {
  print encode($charcode,
        "Usage: 2chproxy [options]\n".
        "\tWebスクレイピングも一応出来るプロクシ。\n".
        "\tLinuxでJD使ってる人用だけど他のでも動くかも。\n".
        "\tこのプロクシはユーザーが保存しているdatファイルを\n".
        "\t読みにいこうとするのでそのユーザー以外での起動は\n".
        "\tあまりおすすめしない。\n".
        "\tOption:\n".
        "\t\t-c|--config file.yaml\n".
        "\t\t\tソース内のPROXY_CONFIG_FILEの代わりにfile.yamlを見に行く\n".
        "\t\t-d|--daemon\n".
        "\t\t\tデーモンとして動かす。バックグラウンドで動くので\n".
        "\t\t\tいちいちターミナルを開きっぱなしにしなくていい。\n".
        "\t\t-h|--help\n".
        "\t\t\tこのテキストを表示する。\n".
        "\t\t-k|--kill\n".
        "\t\t\tすでに起動している2chproxyを終了させる。\n".
        "\t\t\t2chproxy --daemonと書いてあるシェルスクリプトと\n".
        "\t\t\t2chproxy --killと書いてあるシェルスクリプトを用意すると\n".
        "\t\t\tそれぞれ起動用と終了用として使えるかも。\n".
        "\t\t\t時々--killしても2重起動云々と起こられる場合があるけど\n".
        "\t\t\tその時はrm ".$pid_file_name."してくれれば大丈夫なはず。\n".
        "\t\t-p|--parse [file.html]\n".
        "\t\t\tfile.htmlをdat形式に変換して標準出力に出力する。\n".
        "\t\t\t引数を省略した場合は標準入力から読み込む。\n".
        "\t\t-v|--verbose\n".
        "\t\t\t詳細なログを出力する。\n".
        "\t\t--version\n".
        "\t\t\tバージョンを表示する。\n"
      );
  exit 0;
}

sub setting() {
  #stub
  exit 0;
}

sub parse() {
  my %opt = @_;
  my $data;

  &load_config();

  {
    local $/ = undef;

    if ($opt{parse}) {
      my $fh;
      if ( !open($fh, '<', $opt{parse})) {
        print $opt{parse}.': '.($! || $@)."\n";
        exit 1;
      }
      $data = <$fh>;
    }
    else {
      $data = <>;
    }
  }

  $data = Encode::decode('cp932', $data);

  my @array = &html2dat($data);
  print join("\n", @array);

  exit(0);
}

sub version() {
  print encode($charcode,
    "2chproxy.pl ".$version_number."\n".
    "Copyright (C) 2015 ◆okL.s3zZY5iC\n"
  );
  exit 0;
}

#コマンドラインの取得
sub getopt() {
  GetOptions(
    "config|c=s" => sub {
      my ($opt_config, $config_file_name) = @_;
      $PROXY_CONFIG->{PROXY_CONFIG_FILE} = $config_file_name if $config_file_name;
    },
    "daemon|d" => \$is_daemon,
    "help|h" => \&help,
    "kill|k" => \$kill_process,
    "parse|p:s" => \&parse,
    "setting|s" => \&setting,
    "verbose|v" => \$print_verbose,
    "version" => \&version,
  );
}

#既にプロクシが起動しているか
#戻り値:
# 起動している:プロクシのpid
# 起動していない:0
sub is_running() {
  my $lock_file;
  my $pid = 0;

  if (open($lock_file, "<", $pid_file_name)) {
    if (read($lock_file, $pid, -s $pid_file_name)) {
      #取得したpidにシグナルを送れるか確認
      $pid  = int($pid);
      if ($pid <= 0 || !kill('ZERO', $pid)) {
        $pid  = 0;
      }
      &print_log(LOG_INFO, 'PROCESS', "pid: ".$pid."\n");
    }
    close($lock_file);
  }
  undef($lock_file);

  return $pid;
}

#起動中のプロクシを殺す
sub kill() {
  my $pid = shift;
  &print_log(LOG_INFO, 'PROCESS', "kill the process: ".$pid."\n");
  kill('INT', int($pid));
  &cleanup();
}

sub cleanup() {
  if (-f $pid_file_name) {
    unlink($pid_file_name);
  }
}

#シグナルへの対処
sub set_signals() {
  $SIG{PIPE}  = sub {
    my ($package, $filename, $line) = caller;
    #evalの外でcatchするのでdie
    if (threads->tid()) {
      &print_log(LOG_DEBUG, 'SIGNAL', "sigpipe received [$package, $filename, $line]\n");
      die;
    }
  };
  $SIG{INT} = sub {
    &cleanup();
    exit(0);
  };
  $SIG{TERM}  = sub {
    &cleanup();
    exit(0);
  };
}

#デーモン化(*nix向け?)
#そこそこちゃんと作ったけど
#少なくともWinだとうまく動作しない
#いい感じにデーモン化するソフトがあるなら
#そちらを使った方が良い
sub daemonize() {
  fork() and exit(0);
  POSIX::setsid();
  fork() and exit(0);
  umask(022);
  chdir('/');
  open(STDIN, '<', $null_device_name) or die;
  open(STDOUT, '>', $log_file_name) or die;
  open(STDERR, '>&', 'STDOUT') or die;
  chmod(0600, $log_file_name) or die;
  STDOUT->autoflush(1);
  STDERR->autoflush(1);

  return 0;
}

#pidの書き込み
sub exclusive_lock() {
  my $lock_file;

  open($lock_file, ">", $pid_file_name) or die "cannot open pid file: ".$pid_file_name."\n";
  print {$lock_file} $$."\n";
  close($lock_file);
  undef($lock_file);
}

sub add_handler() {
  my %args  = @_;

  if (ref($args{match}) ne 'CODE' &&
      (!blessed($args{match}) || !$args{match}->isa('HTTP::Config'))) {
    #
    return;
  }
  my %handler = (match => $args{match}, data => {}, );
  foreach my $key (qw(request response_header response_done)) {
    if (ref($args{$key}) eq 'CODE') {
      $handler{$key}  = $args{$key};
    }
  }
  push(@handlers, \%handler);
}

sub html2dat() {
  my ($html, $hash_key)  = @_;
  my %cache = &get_mem_cache($hash_key);
  my $title = '';
  my @dat;
  my $res_del_tail_br = '<br><br>';                                     #末尾の<br> <br>を消す
  my $res_del_a = '<a\shref=[^>]+>([^&][^<]*)</a>';                     #安価以外のリンクを消す
  my $res_del_img = '<img\s*src="(?:https?:)?//img\.(\d+)ch\.net/([^"]*)"\s*/?>';  #BEの絵文字をsssp://に
  my $res_replace_oekaki2link = '<img\s*src="(?:https?:)?(//[^.]*\.8ch\.net/[^"]+)"[^>]*>';
  my $dat_del_span = '</?span[^>]*>';
  my $response_regex;
  my $prev_res_number = $cache{dat_last_num} && $cache{dat_last_num}-1 || 0;

  #dat生成部分
  my $make_dat = sub {
    my $line;
    my %var = @_;

    return if ($var{res_number} <= 0);

    &print_log(LOG_DEBUG, 'HTML2DAT', "res_number: ".$var{res_number}."\n");

    $var{date_se_id} =~ s|</span><span[^>]*>| |;

    $var{content} =~ s|$res_del_tail_br||g;
    $var{content} =~ s|$res_del_a|$1|g;
    if ($PROXY_CONFIG->{ENABLE_2CH_TO_nCH} == 2) {
      $var{content} =~ s|$res_del_img|sssp://img.5ch.net/$2|g;
    }
    elsif ($PROXY_CONFIG->{ENABLE_2CH_TO_nCH} == 4) {
      $var{content} =~ s|$res_del_img|sssp://img.2ch.net/$2|g;
    }
    else {
      $var{content} =~ s|$res_del_img|sssp://img.$1ch.net/$2|g;
    }
    $var{content} =~ s|$dat_del_span||g;
    if ($PROXY_CONFIG->{ENABLE_IMG_TO_LINK}) {
      $var{content} =~ s|$res_replace_oekaki2link|[お絵かき] http:$1|g;
    }

    if ($PROXY_CONFIG->{ENABLE_REPLACE_HTTPS_LINK}) {
      my $content = $var{content};  #パターンマッチさせる変数は弄れないので
      my %replace_url_list;
      while ($content =~ m@(h?ttps?://([0-9a-zA-Z]+\.(?:[25]ch\.net|bbspink\.com)/[0-9a-zA-Z/.,-]*))@g) {
        my $url = "http://$2";

        my $regex = qr@h?ttp://\w+\.(\d+ch\.net|bbspink\.com)/[\w/.,-]*@;
        if ($PROXY_CONFIG->{ENABLE_2CH_TO_nCH} == 2) {
          $regex = qr@h?ttp://\w+\.(5ch\.net|bbspink\.com)/[\w/.,-]*@;
        }
        elsif ($PROXY_CONFIG->{ENABLE_2CH_TO_nCH} == 4) {
          $regex = qr@h?ttp://\w+\.(2ch\.net|bbspink\.com)/[\w/.,-]*@;
        }
        #通常のURLなら追加しない
        next if ($1 =~ m@$regex@);

        if ($PROXY_CONFIG->{ENABLE_2CH_TO_nCH} == 2) {
          $url =~ s|\d+ch\.net|5ch.net|;
        }
        elsif ($PROXY_CONFIG->{ENABLE_2CH_TO_nCH} == 4) {
          $url =~ s|\d+ch\.net|2ch.net|;
        }
        $replace_url_list{$url} = 1;
      }
      foreach my $url (keys(%replace_url_list)) {
        $var{content} .= "<br> [Replace URL] $url ";
      }
    }

    if ($var{be1} && $var{be2}) {
      $line = "$var{name_hash}<>$var{email}<>$var{date_se_id} BE:$var{be1}-$var{be2}<>$var{content}<>";
    }
    else {
      $line = "$var{name_hash}<>$var{email}<>$var{date_se_id}<>$var{content}<>";
    }
    if ($var{res_number} == 1) {
      $line .= $var{title};
    }

    if ($prev_res_number + 1 < $var{res_number}) {
      &print_log(LOG_INFO, 'HTML2DAT', "レス番抜けを検出しました\n");
      while (++$prev_res_number < $var{res_number}) {
        push(@dat, 'あぼーん<>あぼーん<>あぼーん<>あぼーん<>');
      }
    }
    elsif ($prev_res_number >= $var{res_number}) {
      #stub
    }
    $prev_res_number = $var{res_number};

    &print_log(LOG_DEBUG, 'HTML2DAT', $line."\n");
    push(@dat, $line);
  };
  
  &print_log(LOG_INFO, 'HTML2DAT', "convert html to dat\n");

  #新read.cgiでは</title>が改行された後にあるのを利用
  if ($html =~ m|$PROXY_CONFIG->{HTML2DAT_TITLE_REGEX}|s) {
    $title = $1;
  }
  else {
    return;
  }

  #タイトルの後に改行コードがあるかどうかで使用する正規表現を変更
  if (!$2) {
    while ($html =~ m|$PROXY_CONFIG->{HTML2DAT_REGEX}|gs) {
      $make_dat->(
        title => $title,
        res_number => int($1),
        email => $2 // "",
        name_hash => $3 // "",
        date_se_id => $4 // "",
        be1 => $5 // "",
        be2 => $6 // "",
        content => $7 // "",
      );
    }
  }
  else{
    while ($html =~ m|$PROXY_CONFIG->{HTML2DAT_REGEX2}|gs) {
      $make_dat->(
        title => $title,
        res_number => ($1),
        email => $2 // "",
        name_hash => $3 // $4 // "",
        date_se_id => $5 // "",
        be1 => $6 // "",
        be2 => $7 // "",
        content => $8 // "",
      );
    }
  }

  if (!$title || scalar(@dat) == 0) {
    #
  }

  return @dat;
}

#保持しているcookieをスカラーの文字列で返す
sub get_cookie() {
  my ($domain)  = @_;
  my @cookie_array;

  if ($PROXY_CONFIG->{ENABLE_2CH_TO_nCH}) {
    $domain =~ s|\.2ch\.net|.5ch.net|;
  }

  &print_log(LOG_INFO, 'COOKIE', 'set cookie for '.$domain."\n");
  foreach my $key (@{$PROXY_CONFIG->{HANDLED_COOKIES}}) {
    lock(%cookie);
    if (exists($cookie{$domain}) && $cookie{$domain}{$key}) {
      &print_log(LOG_INFO, 'COOKIE', 'add cookie: '.$key."\n");
      push(@cookie_array, $key.'='.$cookie{$domain}{$key});
    }
  }
  &print_log(LOG_DEBUG, 'COOKIE', 'cookie_array: '.scalar(@cookie_array)."\n");
  #cookieが存在しない場合はundefを返す
  if (scalar(@cookie_array) == 0) {
    return undef;
  }

  return join("; ", @cookie_array);
}

#Cookieヘッダーの配列からCookieを取り出す
sub extract_cookie() {
  my @headers  = @_;
  my %cookie_args;
  my $domain;

  #受信したクッキーを;で分割してハッシュに代入
  foreach my $header (@headers) {
    foreach my $cookie_arg (split(/;/, $header)) {
      if (my ($key, $value) = $cookie_arg =~ m|[\s]*([^\s]+?)=([^\s]+)|) {
        $cookie_args{$key}  = $value;
      }
    }
  }
  $domain = $cookie_args{domain};
  &print_log(LOG_INFO, 'COOKIE', 'extract cookies from '.$domain."\n");
  {
    lock(%cookie);
    if (!exists($cookie{$domain})) {
      $cookie{$domain}  = &share({});
    }
    foreach my $key (@{$PROXY_CONFIG->{HANDLED_COOKIES}}) {
      if ($cookie_args{$key}) {
        &print_log(LOG_INFO, 'COOKIE', 'cookie found: '.$key."\n");
        $cookie{$domain}{$key} = $cookie_args{$key};
      }
      else {
        &print_log(LOG_DEBUG, 'COOKIE', 'cookie not found: '.$key."\n");
      }
    }
  }
  #特定条件下では保持しているクッキーを削除する
  if ($PROXY_CONFIG->{UNIQ_COOKIE}) {
    lock(%cookie);
    if ($cookie{$domain}{PREN}) {
      delete($cookie{$domain});
    }
  }
}

sub get_cache() {
  my ($host, $domain, $category, $dat) = @_;
  my $hash_key  = $domain.$category.$dat;
  my %cache;
  #メモリ上のキャッシュに前回のアクセス時のものがあればそれを利用
  if ($PROXY_CONFIG->{ENABLE_MEMORY_CACHE}) {
    %cache = &get_mem_cache($hash_key);
    if ($cache{dat_last_num} && $cache{dat_last_str} && $cache{dat_length}) {
      &print_log(LOG_INFO, 'CACHE', "cache found, last res:".$cache{dat_last_str}."\n");
      return %cache;
    }
    &print_log(LOG_INFO, 'CACHE', "cache not found, try to read local dat\n");
  }

  #無い場合はローカルのdatファイルからの読み込みを試みる
  %cache  = &get_local_cache($host, $domain, $category, $dat);
  if ($PROXY_CONFIG->{ENABLE_MEMORY_CACHE}) {
    &set_mem_cache(%cache);
  }

  return %cache;
}

sub set_mem_cache() {
  my ($hash_key, %cache)  = @_;
  lock(%mem_cache);
  if (!$mem_cache{$hash_key}) {
    $mem_cache{$hash_key} = &share({});
  }
  foreach my $key (qw(dat_last_num dat dat_last_str dat_length)) {
    $mem_cache{$hash_key}{$key} = $cache{$key};
  }
  #日付/ID部分がOver 1000 Threadになっているかで過去ログか判定
  if ((split(/<>/, $cache{dat_last_str}))[2] eq 'Over 1000 Thread') {
    &print_log(LOG_INFO, 'SCRAPING', "過去ログ?\n");
    $mem_cache{$hash_key}{dat_kako} = 1;
  }
}

sub clear_mem_cache() {
  my ($hash_key)  = @_;
  lock(%mem_cache);
  delete($mem_cache{$hash_key});
}

sub get_mem_cache() {
  my $hash_key  = shift;
  lock(%mem_cache);
  #参照先を返す
  if (ref($mem_cache{$hash_key}) eq 'HASH') {
    return %{$mem_cache{$hash_key}};
  }
}

sub get_local_cache() {
  my ($host, $domain, $category, $dat) = @_;
  my $local_dat_file_name = &get_local_dat_path($host, $domain, $category, $dat);
  &print_log(LOG_INFO, 'CACHE', 'dat file path: '.$local_dat_file_name."\n");
  my $local_dat_size;
  my %cache;
  my $hash_key  = $domain.$category.$dat;
  my $local_dat_content = &get_local_dat_content($local_dat_file_name);
  if ($local_dat_content) {
    my @local_dat_content_array = split(/\n/, $local_dat_content);
    if ($#local_dat_content_array > 0) {
      {
        $cache{dat_last_num}  = scalar(@local_dat_content_array);
        #内部文字列で保持しておきたいので内部文字列にデコード
        $cache{dat_last_str}  = Encode::decode('cp932', $local_dat_content_array[$#local_dat_content_array]);
        $cache{dat_length}  = length($local_dat_content);
        &print_log(LOG_INFO, 'CACHE', "local dat length: ".$cache{dat_length}."\n");
        &set_mem_cache($hash_key, %cache);
      }
      &print_log(LOG_INFO, 'SCRAPING', "local dat found, last res: ".$cache{dat_last_str}."\n");
    }
  }

  return %cache;
}

#専ブラ依存のdatファイルの場所を返す
#今のところ.2ch.netと.bbspink.com以外のドメインは飛んでこないことを前提としている
sub get_local_dat_path() {
  my ($host, $domain, $category, $dat) = @_;
  my $file_path = "";

  if ($dedicated_browser =~ m@^(?:JD|Navi2ch)$@i) {
    $file_path  = $dat_directory.$host.$domain.'/'.$category.'/'.$dat.'.dat';
  }
  elsif ($dedicated_browser =~ m@^V2C$@i) {
    $domain =~ s|^\.?([^\.]*)\..*|$1_|;
    if ($dat_directory |~ m@/log/@) {
      $dat_directory  .= 'log/';
    }
    $file_path  = $dat_directory.$domain.'/'.$category.'/'.$dat.'.dat';
  }
  elsif ($dedicated_browser =~ m|^Live2ch$|i) {
    if ($dat_directory !~ m|/log/$|) {
      $dat_directory  .= "log/";
    }
    $file_path  = $dat_directory.$host.$domain.'/'.$category.'/'.$dat.'.dat';
  }
  elsif ($dedicated_browser =~ m|^gikoNavi$|i) {
    $domain =~ s|^\.([^\.]*)\..*|$1|;
    #bbspinkも2ch
    if ($domain eq 'bbspink') {
      $domain = '2ch';
    }
    if ($dat_directory !~ m|/Log/$|) {
      $dat_directory  .= 'Log/';
    }
    $file_path  = $dat_directory.$domain.'/'.$category.'/'.$dat.'.dat';
  }
  elsif ($dedicated_browser =~ m|^rep2$|i) {
    #ドメインが.2ch.net、.bbspink.comのどちらの場合も
    #2channelへ変更する
    if ($domain =~ m@(?:\.2ch\.net|\.bbspink\.com)@) {
      $domain = '2channel';
      $file_path  = $dat_directory.$domain.'/'.$category.'/'.$dat.'.dat';
    }
  }
  if (!$file_path) {
    &print_log(LOG_INFO, 'PROXY', "no match type of 専ブラ: ".$dedicated_browser.".\n")
  }

  return $file_path;
}

sub get_local_dat_content() {
  my ($file_name) = @_;
  my $file;
  my $content;

  if (open($file, '<', $file_name)) {
    #スカラー変数にファイルを全部ぶち込むため
    #改行を表す変数をundefにして改行を検知させないようにする
    local $/  = undef;
    $content  = <$file>;
    close($file);
  }
  else {
    return undef;
  }
  undef($file);
  #ギコナビのみ改行コードがCRLFになっているので直す
  if ($dedicated_browser =~ m|^gikoNavi|i) {
    $content =~ s|\r\n|\n|g;
  }

  return $content;
}

#tcpレベルでの通信部分
sub tcp_connection() {
  my ($client, $server) = @_;

  #自動でflushさせる、ブロッキングしない
  $client->autoflush(1);
  $client->blocking(0);
  $server->autoflush(1);
  $server->blocking(0);

  my $rbits_in;    #select(2)で使う、ファイルディスクリプタ(fd)を添字としたビット配列?
  my $wbits_in;    #select(2)で使う
  my $ebits_in;    #select(2)で使うかもしれない

  foreach my $fd (fileno($client), fileno($server)) {
    vec($rbits_in, $fd, 1)  = 1;
  }
  $ebits_in = $rbits_in;

  #それぞれのディスクリプタから相手のディスクリプタを参照出来るようにしておく
  my %fd_pair = (
    fileno($client) => fileno($server),
    fileno($server) => fileno($client),
  );
  my %buffer;         #$buffer{fd}にfdから読み込んだデータを保持
  my $is_buffered;    #バッファが存在するか

  SSL_MAIN_LOOP:
  while(1) {
    #select(2)の準備
    my ($rbits_out, $wbits_out, $ebits_out) = ($rbits_in, $wbits_in, $ebits_in);
    #
    select($rbits_out,
        $wbits_out,
        $ebits_out, undef);

    foreach my $fh ($client, $server) {
      my $fd  = fileno($fh);
      if (vec($rbits_out, $fd, 1)) {
        my $rlen  = sysread($fh, $buffer{$fd}, $tcp_connection_buffer, length($buffer{$fd}));
        &print_log(LOG_DEBUG, 'HTTPS', "read ".$rlen."bytes\n");
        #バッファがたまったら書き込み先のfdをwbitsに登録
        if ($rlen > 0) {
          vec($wbits_in, $fd_pair{$fd}, 1)  = 1;
        }
        elsif (defined($rlen) && $rlen == 0) {
          &print_log(LOG_DEBUG, 'HTTPS', "fd closed\n");
          last SSL_MAIN_LOOP;
        }
      }
      #
      if (vec($wbits_out, $fd, 1)) {
        my $wlen  = syswrite($fh, $buffer{$fd_pair{$fd}});
        &print_log(LOG_DEBUG, 'HTTPS', "write ".$wlen."bytes\n");
        #すべて書き込んだ場合はバッファを削除
        if ($wlen == length($buffer{$fd_pair{$fd}})) {
          undef($buffer{$fd_pair{$fd}});
          vec($wbits_in, $fd, 1)  = 0;
        }
        elsif ($wlen > 0 && $wlen < $buffer{$fd_pair{$fd}}) {
          $buffer{$fd_pair{$fd}}  = substr($buffer{$fd_pair{$fd}}, $wlen);
        }
      }
    }
  }
}

#httpsな通信
sub ssl_connection() {
  my ($client_ref, $request_ref, $dport)  = @_;
  my $client  = $$client_ref;
  my $request = $$request_ref;
  my $uri = $request->uri;
  #CONNECTメソッドなので繋ぐだけ
  my $socket  = IO::Socket::INET->new(
    PeerAddr => $uri->host,
    PeerPort => $dport,
    Proto => 'tcp'
  ) or return $@;

  #クライアントへ200 Connection establishedを返す
  &print_log(LOG_INFO, 'HTTPS', "return connection established\n");
  my $connection_established_str  = $request->protocol." 200 Connection established\r\n\r\n";
  syswrite($client, $connection_established_str);
  #通信の中身を見ずにtcpレベルで通信させる
  &tcp_connection($client, $socket);
  &print_log(LOG_INFO, 'HTTPS', "finished ssl connection\n");
  #$clientはconnection()側で処理するのでこちら側ではcloseしない
  close($socket);
  undef($socket);

  return undef;
}

#通信部分
sub connection() {
  my $client  = shift;
  my $user_agent = LWP::UserAgent->new(keep_alive => 1);
  my $keep_alive  = 1;
  my $conn_cache;
  eval {
    require LWP::ConnCache;
  };
  if (!$@) {
    $conn_cache  = LWP::ConnCache->new();
    $conn_cache->total_capacity($PROXY_CONFIG->{MAXIMUM_CONNECTIONS});
    $user_agent->conn_cache($conn_cache);
  }

  #UAが無いリクエストで勝手にUAを追加しないように抑制する
  $user_agent->agent('');
  #タイムアウト値を設定
  if ($PROXY_CONFIG->{TIMEOUT}) {
    $user_agent->timeout($PROXY_CONFIG->{TIMEOUT});
  }
  #上位プロクシの設定(FORWARD_PROXY(http,httpsのみ)、環境変数)
  #優先順位はFORWARD_PROXY > 環境変数
  $user_agent->env_proxy();
  if ($PROXY_CONFIG->{FORWARD_PROXY}) {
    $user_agent->proxy([qw(http https)], $PROXY_CONFIG->{FORWARD_PROXY});
  }
  #&print_log(LOG_INFO, 'PROXY', "start connection.\n");

  REQUEST_LOOP:
  while ($keep_alive && (my $request  = $client->get_request())) {
    #接続先の表示
    &print_log(LOG_INFO, 'HTTP', $client->sockhost." | ".$request->method." ".$request->uri->as_string()."\n");
    my $uri = $request->uri;
    my $dport;

    if ($uri->can('port')) {
      $dport  = $uri->port;
      &print_log(LOG_DEBUG, 'HTTP', "destination port: ".$dport."\n");
    }

    #443ポートへのCONNECTのみhttps通信として取り扱う
    if ($request->method eq 'CONNECT') {
      if ($dport != 443) {
        $client->send_response(HTTP::Response->new(403, 'Forbidden'));
        last;
      }
      #オプションで無効にされている場合は501 Not Implementedを返す
      if ($PROXY_CONFIG->{ALLOW_CONNECT_METHOD}) {
        my $err = &ssl_connection(\$client, \$request, $dport);
        if ($err) {
          &print_log(LOG_INFO, 'HTTPS', $err."\n");
          my $response  = HTTP::Response->new(500, $err);
          $client->send_response($response);
        }
      }
      else {
        my $response  = HTTP::Response->new(501, 'Not Implemented');
        $client->send_response($response);
      }
      last;
    }

    foreach my $connection_header ($request->header('Connection')) {
      $request->remove_header($connection_header);
    }

    my $client_protocol = $request->protocol();
    if ($client_protocol lt 'HTTP/1.1' ||
        $request->header('Connection') ne 'keep-alive' ||
        !$conn_cache) {
      $keep_alive = 0;
    }

    my %valid_handler = (
      handlers =>[],
      request => 0,
      response_header => 0,
      response_done => 0,
    );

    my $orig_request = $request->clone; #


    MATCH_REQUEST:
    #リクエストがハンドラが処理したいものかどうか判定
    foreach my $handler (@handlers) {
      eval {
        if (ref($handler->{match}) eq 'CODE') {
          $handler->{is_matched}  = &{$handler->{match}}($orig_request->clone, $handler->{data});
        }
        #HTTP::Config
        else {
          $handler->{is_matched}  = $handler->{match}->matching($orig_request->clone);
        }
        if ($handler->{is_matched}) {
          foreach my $key (qw(request response_header response_done)) {
            if (defined($handler->{$key})) {
              $valid_handler{$key}++;
            }
          }
          push(@{$valid_handler{handlers}}, $handler);
        }
      };
      if ($@) {
        &print_log(LOG_NOTICE, $@);
      }
    }

    #responseを受信しきってからクライアントへ送るかのフラグ
    my $buffered  = $valid_handler{response_done};

    if ($valid_handler{request}) {
      my $tmp_request;
      REWRITE_REQUEST:
      foreach my $handler (@{$valid_handler{handlers}}) {
        eval {
          if (defined($handler->{request})) {
            $tmp_request  = $request->clone;
            my $response  = $handler->{request}($request, $handler->{data});
            if (!blessed($response)) {
              next REWRITE_REQUEST;
            }
            elsif ($response->isa('HTTP::Response')) {
              $request  = $response;
              last REWRITE_REQUEST;
            }
            else {
              $request  = HTTP::Response->new(500, 'Proxy Error');
              last REWRITE_REQUEST;
            }
          }
        };
        if ($@) {
          &print_log(LOG_NOTICE, 'PROXY', $@);
          $request  = $tmp_request;
        }
      }
    }

    if (!$request->isa('HTTP::Request')) {
      $client->send_response($request);
      next REQUEST_LOOP;
    }

    if ($client_protocol lt 'HTTP/1.1') {
      &print_log(LOG_INFO, 'PROXY', $client_protocol." -> HTTP/1.1\n");
      $request->protocol('HTTP/1.1');
      $request->header('Connection' => 'keep-alive');
      if (!$request->header('Host') && $request->uri->can('host')) {
        $request->header('Host' => $request->uri->host());
      }
    }

    #HTTP/1.1のkeep-alive以外は全てConnection: closeにする
    if (!$keep_alive) {
      $request->header('Connection' => 'close');
    }

    &print_log(LOG_DEBUG, 'HTTP', $request->as_string."\n");

    my $chunked = 0;

    $user_agent->set_my_handler('response_header' => sub {
        my ($response, $ua, $h) = @_;

        &print_log(LOG_NOTICE, 'HTTP', $response->protocol." ".$response->status_line." | ".$response->request->method." ".$response->request->uri->as_string."\n");

        #HTTP/1.1のkeep-alive以外はConnection: close
        if (!$keep_alive ||
            $response->header('Connection') ne 'keep-alive' ||
            $response->protocol() lt 'HTTP/1.1') {
          $response->header('Connection' => 'close');
          $keep_alive = 0;
        }

        if (defined($response->header('Client-Transfer-Encoding'))) {
          $response->header('Transfer-Encoding' => $response->remove_header('Client-Transfer-Encoding'));
          #HTTP/1.1以前はTransfer-Encodingが無いので削除
          #全部受信しきる場合もContent-Lengthを使うので同様に削除
          if ($client_protocol lt 'HTTP/1.1' || $buffered) {
            $response->remove_header('Transfer-Encoding');
          }
          else {
            &print_log(LOG_INFO, 'HTTP', "chunked detected, content return as chunked\n");
            #優先度はTransfer-Encoding > Content-Length
            $response->remove_header('Content-Length');
            $chunked  = 1;
          }
        }

        #Client-*ヘッダーは削除
        foreach my $header (qw(Client-Peer Client-Response-Num)) {
          if ($response->remove_header($header)) {
            #
          }
        }

        if ($valid_handler{response_header}) {
          REWRITE_RESPONSE_HEADER:
          foreach my $handler (@{$valid_handler{handlers}}) {
            eval {
              if (defined($handler->{response_header})) {
                $handler->{response_header}($response, $handler->{data});
              }
            };
            if ($@) {
              &print_log(LOG_NOTICE, 'PROXY', $@);
            }
          }
        }

        #"\r\n"の指定はした方が良い
        my $header  = $response->as_string("\r\n");
        &print_log(LOG_DEBUG, 'HTTP', $header);
        if (!$buffered) {
          print {$client} $header;
        }
      },
      owner => '2chproxy',
    );

    my $response  = $user_agent->simple_request($request,
      sub {
        my ($chunk_data, $response, $proto) = @_;

        if ($buffered) {
          $response->add_content($chunk_data);
        }
        #バッファしない場合は逐次送信
        else {
          if ($chunked) {
            &print_log(LOG_DEBUG, 'HTTP', sprintf("chunked %x", length($chunk_data))."\n");
            print {$client} sprintf('%x', length($chunk_data))."\r\n".$chunk_data."\r\n";
          }
          else {
            print {$client} $chunk_data;
          }
        }
      }
    );

    #chunkedのフッターはここで送る
    if ($chunked) {
      &print_log(LOG_DEBUG, 'HTTP', "send chunked footer\n");
      print {$client} "0\r\n\r\n";
    }
    if ($response->header('X-Died')) {
      &print_log(LOG_NOTICE, 'HTTP', "An Error Occured: ".$response->header('X-Died')."\n");
    }

    #受信しきる場合でクライアントが死んでそうなら通信を終了する
    if (!$client->connected) {
      &print_log(LOG_INFO, 'HTTP', "client seems to be closed\n");
      last REQUEST_LOOP;
    }

    #削除
    $user_agent->set_my_handler('response_header' => undef, owner => '2chproxy');

    if ($valid_handler{response_done}) {
      #通信後のresponseの書き換え処理
      REWRITE_RESPONSE_DONE:
      foreach my $handler (@{$valid_handler{handlers}}) {
        eval {
          if (defined($handler->{response_done})) {
            &print_log(LOG_INFO, 'PROXY', "change response\n");
            my $tmp_response  = $handler->{response_done}($response, $handler->{data});
            #
            if (blessed($tmp_response) && $tmp_response->isa('HTTP::Response')) {
              $response = $tmp_response;
            }
          }
        };
        if ($@) {
          &print_log(LOG_NOTICE, 'PROXY', $@);
        }
      }
    }

    if ($buffered) {
      $client->send_response($response);
    }
  }
  close($client);
  undef($client);
  undef($user_agent);
  &print_log(LOG_INFO, 'HTTP', "finish connection.\n");
}

#一部のドメインへの接続はUAとクッキーを変更する
sub change_access_Nch_match() {
  my $request  = shift;

  if ($request->uri->host =~ m@(\.\d+ch\.net|\.bbspink\.com)$@) {
    return 1;
  }
  return 0;
}

sub change_access_Nch_request() {
  my $request = shift;

  if ($request->uri->host =~ m@(\.\d+ch\.net|\.bbspink\.com)$@) {
    my $domain  = $1;
    if ($PROXY_CONFIG->{USER_AGENT}) {
      &print_log(LOG_INFO, 'PROXY', 'change user-agent:'.$request->header('User-Agent')."->".$PROXY_CONFIG->{USER_AGENT}."\n");
      $request->header('User-Agent' => $PROXY_CONFIG->{USER_AGENT});
    }
    #クッキーが専ブラによって指定されていない場合は設定する
    if ($PROXY_CONFIG->{KEEP_COOKIE}) {
      my $cookie_str  = &get_cookie($domain);
      if ($cookie_str) {
        if ($request->header('Cookie')) {
          $cookie_str = $request->header('Cookie')."; ".$cookie_str;
        }
        &print_log(LOG_INFO, 'COOKIE', 'Cookie: '.$cookie_str."\n");
        $request->header('Cookie' => $cookie_str);
      }
    }
    if ($PROXY_CONFIG->{ENABLE_2CH_TO_nCH}) {
      my $url = $request->uri->as_string;
      $url =~ s|\.2ch\.net|.5ch.net|;
      $request->uri($url);
      my $host = $request->header('Host');
      if ($host) {
        $host =~ s|\.2ch\.net|.5ch.net|;
        $request->header('Host' => $host);
      }
      my $referer = $request->header('Referer');
      if ($referer) {
        $referer =~ s|\.2ch\.net|.5ch.net|;
        $request->header('Referer' => $referer);
      }
      &print_log(LOG_INFO, '2ch to Nch', 'rewrite_uri: '.$url."\n");
    }
  }
}

sub change_access_Nch_response() {
  my $response = shift;

  #一部ドメインへの接続はクッキーを保存する
  if ($PROXY_CONFIG->{KEEP_COOKIE} && $response->header('Set-Cookie')) {
    &print_log(LOG_INFO, 'COOKIE', "Set-Cookie header found\n");
    &extract_cookie($response->header('Set-Cookie'));
  }
}

sub bbsmenu_tolower_match() {
  my ($request, $data)  = @_;
  if ($request->uri->as_string =~ m|^https?://menu\.\d+ch\.net(?::80)?/bbsmenu\.html$|) {
    return 1;
  }
  return 0;
}

sub bbsmenu_tolower_response() {
  my ($response, $data) = @_;
  my $fallback_charset  = 'cp932';
  my $charset = $fallback_charset;
  if ($enable_guess_encoding) {
    $charset  = 'Guess';
  }

  my $content;
  eval {
    $content  = $response->decoded_content(charset => $charset, charset_strict => 1, raise_error => 1,);
  };
  if ($@) {
    $content  = $response->decoded_content(charset => $fallback_charset);
  }
  #可能なら専ブラ側で対応した方が良い気がする
  {
    #HTMLを解釈している方
    $content  =~ s|<a |<A |;                  #bb-chat.tv
    $content  =~ s|</FONT>|</font>|g;
    #$content  =~ s|<(/)?([a-zA-Z]+)(\s[^>]+)?>|<$1\L$2\E$3>|g;
  }
  {
    #正規表現やその類で抽出している方
    $content  =~ s|<A HREF="(.*)">|<A HREF=$1>|g
  }
  if ($PROXY_CONFIG->{ENABLE_2CH_TO_nCH} >= 3) {
    $content  =~ s|https?://(\w+)\.\d+ch\.net/|http://$1.2ch.net/|g;
  }
  $response->remove_header('Content-Encoding');
  $response->content(Encode::encode('cp932', $content, Encode::FB_HTMLCREF));

  return $response;
}

sub thread_title_search_match() {
  my ($request, $data)  = @_;
  if ($PROXY_CONFIG->{THREAD_TITLE_SEARCH_URL}) {
    my $url = URI->new($PROXY_CONFIG->{THREAD_TITLE_SEARCH_URL})->canonical->as_string;
    if ($request->uri->canonical->as_string =~ m|$url|) {
      return 1;
    }
  }
  return 0;
}

sub thread_title_search_response() {
  my ($response, $data) = @_;
  my $content;

  #gzip等のデコードのみ行う
  if (!$response->decode()) {
    return;
  }
  #置換の対象になる部分はASCIIのみであるため
  #文字コード判別の必要は無い
  $content  = $response->content();

  if ($PROXY_CONFIG->{ENABLE_2CH_TO_nCH} == 1 || $PROXY_CONFIG->{ENABLE_2CH_TO_nCH} == 2) {
    &print_log(LOG_INFO, 'THREAD SEARCH', "2ch->5ch\n");
    $content =~ s|https?://([0-9a-zA-Z]+)\.2ch\.net/|http://$1.5ch.net|g;
  }
  elsif ($PROXY_CONFIG->{ENABLE_2CH_TO_nCH} == 3 || $PROXY_CONFIG->{ENABLE_2CH_TO_nCH} == 4) {
    &print_log(LOG_INFO, 'THREAD SEARCH', "5ch->2ch\n");
    $content =~ s|https?://([0-9a-zA-Z]+)\.5ch\.net/|http://$1.2ch.net|g;
  }
  $response->content($content);
}

sub scraping_2ch_match() {
  my $request  = shift;
  if ($PROXY_CONFIG->{ENABLE_WEB_SCRAPING} && ( ($request->uri->as_string =~ m|$PROXY_CONFIG->{DAT_URL}|) && ($1 ne 'headline') ) ) {
    return 1;
  }
  return 0;
}

#スクレイピング部分
sub scraping_2ch_request() {
  my ($request, $data) = @_;
  my $host;
  my $domain;
  my $category;
  my $path;
  my $dat;
  my $is_gzip;
  my $uri = $request->uri;
  my $last_res;         #リクエストされたURIに対するメモリ上のキャッシュ/ローカルのdatファイルの中で最新のレス

  #URLをハッシュのキーにしようと思ったけど一部板で
  #host名が違っても同じデータを寄越すものがあったので
  #(kilauea.bbspink.comとaoi.bbspink.com、他にも板移転があった場合?)
  #ドメイン、カテゴリ、datの3つをハッシュのキーに設定
  my $hash_key;
  my $rewrite_uri;
  my $range;
  my $expected_partial_content;
  my $expected_head_response;

  if ($uri->as_string =~ m|$PROXY_CONFIG->{DAT_URL}|) {
    $host = $1;
    $domain = $2;
    $category = $4;
    $dat  = $5;
    $is_gzip  = $6;

    $hash_key  = $domain.$category.$dat;
    $rewrite_uri  = $uri->scheme()."://".$host.$domain."/test/read.cgi/".$category."/".$dat."/";
  }
  else {
    my $response  = HTTP::Response->new(500, 'Invalid URL');
    return $response;
  }

  #HEADでdatが更新されたかのみを確認する場合は
  #レスポンスからコンテンツを取り除く
  if ($request->method eq 'HEAD') {
    &print_log(LOG_INFO, 'SCRAPING', 'change method: '.'HEAD'.'->'.'GET'."\n");
    $expected_head_response = 1;
    $request->method('GET');
  }
  #スクレイピング時にENABLE_PARTIAL_CONTENTを有効にしていれば
  #Rangeヘッダーを見に行って差分取得を行う
  if ($PROXY_CONFIG->{ENABLE_PARTIAL_CONTENT} && $request->header('Range') =~ m|^bytes=(\d+)-$|) {
    $range  = $1;
    &print_log(LOG_INFO, 'SCRAPING', 'Range header found: '.$range.'-'."\n");
    my %cache = &get_cache($host, $domain, $category, $dat);
    #html2datの最中に専ブラ側が接続を切ると
    #キャッシュが専ブラ側と食い違う場合があるのでその場合はキャッシュし直す
    #これでは対応出来ない専ブラがあるかもなので要検証
    my $tmp_str = Encode::encode('cp932', $cache{dat_last_str});
    #if ($cache{dat_length} != $range+1) {
    if ($range <= $cache{dat_length} - length($tmp_str) &&
        $range > $cache{dat_length}) {
      &print_log(LOG_INFO, 'CACHE', "キャッシュにズレが生じています\n");
      &clear_mem_cache($hash_key);
      %cache = &get_cache($host, $domain, $category, $dat);
    }
    $last_res = $cache{dat_last_str};
    $rewrite_uri  .= $cache{dat_last_num}."-n";

    #メモリ上にもローカルにも差分取得のための情報が無い場合は
    #全レス取得してそこからRangeの該当部分を返す
    if (!$last_res) {
      $expected_partial_content = 1;
    }
    elsif ($cache{dat_kako}) {
      &print_log(LOG_INFO, 'SCRAPING', "過去ログ?\n");
      return HTTP::Response->new(304, 'Not Modified');
    }
  }
  &print_log(LOG_INFO, 'SCRAPING', 'rewrite_uri: '.$rewrite_uri."\n");
  $request->uri($rewrite_uri);

  #416を応答されないようにRangeヘッダーを削除
  my $range_header;
  if ($request->header('Range')) {
    $range_header = $request->remove_header('Range');
  }

  $data->{uri}                      = $uri;
  $data->{is_gzip}                  = $is_gzip;
  $data->{last_res}                 = $last_res;
  $data->{range}                    = $range;
  $data->{hash_key}                 = $hash_key;
  $data->{expected_head_response}   = $expected_head_response;
  $data->{expected_partial_content} = $expected_partial_content;
}

sub scraping_2ch_response() {
  my ($response, $data) = @_;

  my $is_gzip                   = $data->{is_gzip};
  my $last_res                  = $data->{last_res};
  my $range                     = $data->{range};
  my $hash_key                  = $data->{hash_key};
  my $expected_head_response    = $data->{expected_head_response};
  my $expected_partial_content  = $data->{expected_partial_content};
  my $uri                       = $data->{uri};

  #20x以外の応答は何もせずにクライアントへ返す
  if (!$response->is_success()) {
    &print_log(LOG_NOTICE, 'HTTP', "Server didn't return 20x\n");
    return $response;
  }

  #Last-Modifiedヘッダーが無い場合は
  #Dateヘッダーの値をコピーする
  if (!$response->header('Last-Modified')) {
    &print_log(LOG_INFO, 'SCRAPING', "add Last-Modified header\n");
    $response->header('Last-Modified' => $response->header('Date'));
  }
  #Dateがダブっているので片方削除
  $response->remove_header('Date');

  my $fallback_charset  = 'cp932';
  my $charset = $fallback_charset;
  if ($enable_guess_encoding) {
    $charset  = 'Guess';
  }
  &print_log(LOG_INFO, 'SCRAPING', "charset: ".$charset."\n");

  my $response_content;
  eval {
    $response_content = $response->decoded_content(charset => $charset, charset_strict => 1, raise_error => 1,);
  };
  if ($@) {
    $response_content = $response->decoded_content(charset => $fallback_charset);
  }

  my @content_array  = &html2dat($response_content, $hash_key);
  &print_log(LOG_INFO, 'SCRAPING', "size of content_array: ".scalar(@content_array)."\n");

  #chunkedは消毒だー
  foreach my $header (qw(Transfer-Encoding Client-Transfer-Encoding)) {
    if (defined($response->header($header))) {
      &print_log(LOG_INFO, 'HTTP', $header." defined.\n");
      $response->remove_header($header);
    }
  }

  my $content;
  #last_resが存在する==クライアントには206を返すべきである
  if ($last_res) {
    my $first_res;          #デバッグ用、受信した中で最初のレス
    $first_res  = shift(@content_array);
    #空白の個数が違ったりするので
    #空白は連続しないように切り詰める
    $last_res   =~ tr/ //s;
    $first_res  =~ tr/ //s;
    #取得レス数が1個だった、かつfirst_resが存在するなら
    #更新していないので304を返す
    if (scalar(@content_array) == 0 && $first_res) {
      &print_log(LOG_INFO, 'SCRAPING', "content not modified\n");
      $response = HTTP::Response->new(304, 'Not Modified');

      return $response;
    }
    #更新が存在する場合は前回通信時での最新のレスと
    #今回通信時の最初のレスが一致していれば206を返す
    elsif ($last_res eq $first_res) {
      {
        my %cache  = &get_mem_cache($hash_key);
        #Rangeの値として不適切(というかクライアント側でファイルが壊れている云々と言うはず)
        #なので416を返す
        if ($range > $cache{dat_length}) {
          &print_log(LOG_NOTICE, 'SCRAPING', 'invalid range: '.$range."\n");
          &print_log(LOG_NOTICE, 'SCRAPING', 'dat length: '.$cache{dat_length}."\n");
          $response = HTTP::Response->new(416, 'Requested Range Not Satisfiable');
          #メモリのキャッシュを削除
          %cache  = ();
          &set_mem_cache($hash_key, %cache);

          return $response;
        }
        #rangeの方が小さい時(専ブラがエラー検出を行おうとしている時)は
        #その分だけ前回の最新のレスからコピーする
        #前回の最新のレスより大きなbyte数でエラー検出を行おうとしている場合は
        #*未定義*
        #(多分クライアントが"ファイルが壊れている"と言うはず)
        elsif ($range < $cache{dat_length}) {
          my $error_detection  = Encode::encode('cp932', $cache{dat_last_str}."\n");
          $content  = substr($error_detection, $range-$cache{dat_length});
        }
        $content  .= Encode::encode('cp932', join("\n", @content_array)."\n", Encode::FB_HTMLCREF);
        #差分を取得した分だけメモリのキャッシュを更新する
        #ただし更新チェックのみ(methodがHEADなリクエスト)だった場合は更新しない
        if (!$expected_head_response) {
          my %cache = &get_mem_cache($hash_key);
          $cache{dat_last_num}  += scalar(@content_array);
          $cache{dat_last_str}  = pop(@content_array);
          $cache{dat_length}  = $range+length($content);
          &set_mem_cache($hash_key, %cache);
        }
      }
      &print_log(LOG_INFO, 'SCRAPING', "content returned as partial content\n");
      $response->code(206);
      $response->message('Partial Content');
      #206用のヘッダーを追加
      $response->header('Accept-Range' => 'bytes');
      &print_log(LOG_INFO, 'SCRAPING', 'add header Content-Range: '.'bytes '.$range.'-'.($range+length($content)-1).'/'.($range+length($content))."\n");
      $response->header('Content-Range' => 'bytes '.$range.'-'.($range+length($content)-1).'/'.($range+length($content)));
    }
    #レスが一致していないので416を返す
    else {
      &print_log(LOG_NOTICE, 'SCRAPING', "responses don't match\n");
      &print_log(LOG_INFO, 'SCRAPING', "last  res: ".$last_res."\n");
      &print_log(LOG_INFO, 'SCRAPING', "first res: ".$first_res."\n");
      $response = HTTP::Response->new(416, 'Requested Range Not Satisfiable');
      #メモリのキャッシュを削除する
      {
        &clear_mem_cache($hash_key);
      }

      return $response;
    }
  }
  #全レス取得時
  else {
    #html2datでの変換に失敗、または2ch側がエラーを返してきた
    #(datが見つかりません的なもの)場合は302を返す
    #info.2ch.net/index.php/Monazilla/develop/dat#未稿によれば
    #302になる度.dat->kako.dat.gz->kako.dat[->offlaw.cgi]の順に使用
    if (!@content_array || !$content_array[0]) {
      &print_log(LOG_NOTICE, 'SCRAPING', "broken content\n");
      $response = HTTP::Response->new(302, 'Found');
      #元のuriから次にLocationとして設定すべきuriを生成するのが面倒なので
      #人大杉のurlを返しておく
      #上コメント内のurlを見る限りではLocationヘッダーは見ないのだと思うが
      #Locationヘッダーを見る専ブラはもしかしたらうまく過去ログ参照しないかも
      $response->header('Location' => 'http://www2.2ch.net/live.html');
      return $response;
    }
    $content  = Encode::encode('cp932', join("\n", @content_array)."\n", Encode::FB_HTMLCREF);
    {
      my %cache;
      $cache{dat_last_num}  = scalar(@content_array);
      &print_log(LOG_INFO, 'SCRAPING', "last num: ".scalar(@content_array)."\n");
      $cache{dat_last_str}  = pop(@content_array);
      &print_log(LOG_INFO, 'SCRAPING', "last str: ".$cache{dat_last_str}."\n");
      $cache{dat_length}  = length($content);
      &print_log(LOG_INFO, 'SCRAPING', "length: ".length($content)."\n");

      &set_mem_cache($hash_key, %cache);
    }

    if ($expected_partial_content) {
      #リクエストにRangeヘッダーがあり206を返すのが期待されている場合は
      #Rangeの範囲にあわせて206,416のどちらかを返す
      if ($range < length($content)) {
        &print_log(LOG_INFO, 'SCRAPING', "content returned as partial content\n");
        $content  = substr($content, $range);
        $response->code(206);
        $response->message('Partial Content');
        #206用のヘッダーを追加
        $response->header('Accept-Range' => 'bytes');
        &print_log(LOG_INFO, 'SCRAPING', 'add header Content-Range: '.'bytes '.$range.'-'.($range+length($content)-1).'/'.($range+length($content))."\n");
        $response->header('Content-Range' => 'bytes '.$range.'-'.($range+length($content)-1).'/'.($range+length($content)));
      }
      #Rangeの範囲がおかしいので416を返す
      else {
        my %cache  = &get_mem_cache($hash_key);
        &print_log(LOG_NOTICE, 'SCRAPING', 'invalid range: '.$range."\n");
        &print_log(LOG_NOTICE, 'SCRAPING', 'dat length: '.$cache{dat_length}."\n");
        $response = HTTP::Response->new(416, 'Requested Range Not Satisfiable');
        #メモリのキャッシュを削除する
        {
          &clear_mem_cache($hash_key, %cache);
        }
        return $response;
      }
    }
    #urlが.dat.gzだった場合はレスポンスの本体をgzipに圧縮する
    #Content-Typeをapplication/gzipにすることを忘れずに
    #過去ログはRangeが送られてこないはずなので処理部分はここだけでよいはず
    elsif ($is_gzip && !$PROXY_CONFIG->{DISABLE_GZIP_COMPRESS}) {
      my $tmp;
      if (gzip \$content => \$tmp) {
        $content  = $tmp;
        $response->header('Content-Type' => 'application/gzip');
      }
      #gzip圧縮に失敗した場合は500を返す
      else {
        &print_log(LOG_ERR, 'SCRAPING', $GzipError."\n");
        $response = HTTP::Response->new(500, 'Internal Server Error');
        return $response;
      }
    }
  }

  #要求がHEADだった場合はContentに関するものを削除する
  if ($expected_head_response) {
    $content  = $response->content_ref;
    undef $content;
    $response->remove_header('Content-Length');
    if ($response->header('Content-Encoding')) {
      $response->remove_header('Content-Encoding');
    }
    $response->remove_header('Content-Type');
  }
  else {
    $response->content($content);
    $response->header('Content-Length' => length($content));
    if ($response->header('Content-Encoding')) {
      $response->remove_header('Content-Encoding');
    }
    #クライアントがgzipで圧縮したものを要求している場合は変更しない
    if (!$is_gzip && ($response->header('Content-Type') ne 'application/gzip') ) {
      $response->header('Content-Type' => 'text/plain');
    }
  }

  return $response;
}

sub replace_be_auth_match() {
  my $request = shift;
  return $PROXY_CONFIG->{ENABLE_REPLACE_BE_AUTH_RESPONSE} && $request->uri->as_string =~ m|://be\.[25]ch\.net(?::\d+)/test/login\.php|;
}

sub replace_be_auth_response(){
  my $response = shift;
  return if ($response->code ne 302);
  &print_log(LOG_INFO, 'be response', "detected be auth response\n");
  $response->code(200);
}

#
sub run_proxy() {
  my $proxy = HTTP::Daemon->new(
    LocalHost => $PROXY_CONFIG->{LISTEN_HOST},
    LocalPort => $PROXY_CONFIG->{LISTEN_PORT},
    Listen  => $PROXY_CONFIG->{MAXIMUM_CONNECTIONS},
    ReuseAddr => 1, #
  );

  if (!$proxy) {
    if (-f $pid_file_name) {
      unlink $pid_file_name;
    }
    die;
  }

  &print_log(LOG_NOTICE, 'PROCESS', "listen to ".$proxy->url."\n");
  while (my $client = $proxy->accept()) {
    &print_log(LOG_INFO, 'HTTP', "request received.\n");
    $client->autoflush(1);
    my $thread  = threads->new(sub {
        my $client  = shift;
        $semaphore->down(1);
        eval {
          \&connection($client);
        };
        if ($@) {
          &print_log(LOG_WARN, $@."\n");
        }
        $semaphore->up(1);
      }, $client);
    $thread->detach();
    undef($client);
    #最大接続数を超える場合は現在の処理が終わるまで待つ
    $semaphore->down(1);
    $semaphore->up(1);
  }
}

sub load_config() {
  if ($PROXY_CONFIG->{PROXY_CONFIG_FILE} && -f $PROXY_CONFIG->{PROXY_CONFIG_FILE}) {
    require YAML::Tiny;
    my $YAML  = YAML::Tiny->read($PROXY_CONFIG->{PROXY_CONFIG_FILE});
    if ($YAML && $YAML->[0]) {
      foreach my $key (keys(%$PROXY_CONFIG)) {
        if (exists($YAML->[0]{$key})) {
          if ($YAML->[0]{$key} ne $PROXY_CONFIG->{$key}) {
            if (!ref($PROXY_CONFIG->{$key})) {
              &print_log(LOG_INFO, 'CONFIG', $key.": ".$PROXY_CONFIG->{$key}." -> ".$YAML->[0]{$key}."\n");
            }
            else {
              &print_log(LOG_INFO, 'CONFIG', $key."[".ref($PROXY_CONFIG->{$key})."] changed\n");
            }
            $PROXY_CONFIG->{$key} = $YAML->[0]{$key};
          }
          else {
            &print_log(LOG_DEBUG, 'CONFIG', $key.": no change\n");
          }
        }
      }
      #コンフィグファイルの読み込みに成功したらグローバル変数を一新する
      &initialize_global_var();
    }
  }
  else {
    &print_log(LOG_INFO, 'CONFIG', "config file: ".$PROXY_CONFIG->{PROXY_CONFIG_FILE}." is not found.\n");
  }
}

#初期化処理
sub initialize() {
  #コンフィグファイルの読み込み
  &load_config();
  #2重起動しているかの確認,起動中のプロクシの制御
  my $pid = &is_running();
  if ($kill_process) {
    if ($pid) {
      &kill($pid);
    }
    exit(0);
  }
  if ($pid) {
    &print_log(LOG_ERR, 'PROCESS', basename($0)." is already running.\n");
    &print_log(LOG_ERR, 'PROCESS', "if you kill ".basename($0).", please run this command: ".basename($0)." --kill\n");
    &print_log(LOG_ERR, 'PROCESS', "or : rm ".$pid_file_name."\n");
    exit 1;
  }

  #プロセスのデーモン化
  if ($is_daemon) {
    &daemonize();
  }
  #2重起動の防止
  &exclusive_lock();
  #シグナルの設定
  &set_signals();

  #handlerの設定
  &add_handler(
    match => \&bbsmenu_tolower_match,
    response_done => \&bbsmenu_tolower_response,
  );
  &add_handler(
    match => \&scraping_2ch_match,
    request => \&scraping_2ch_request,
    response_done => \&scraping_2ch_response,
  );
  &add_handler(
    match => \&thread_title_search_match,
    response_done => \&thread_title_search_response,
  );
  &add_handler(
    match => \&change_access_Nch_match,
    request => \&change_access_Nch_request,
    response_header => \&change_access_Nch_response,
  );
  &add_handler(
    match => \&replace_be_auth_match,
    response_header => \&replace_be_auth_response,
  );
}

#main
{ 
  #グローバル変数の初期化
  &initialize_global_var();

  &getopt();

  &initialize();
  &run_proxy();
}


__END__

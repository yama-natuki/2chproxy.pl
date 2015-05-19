#!/usr/bin/perl
 
#Copyright (c) 2015 ◆okL.s3zZY5iC
#Released under the MIT license
#http://opensource.org/licenses/mit-license.php
 
#v0.17.1からの変更点
# v0.17及びv0.17.1でContent-Lengthの値が0なレスポンス(したらば等)をクライアントへ返していない問題を修正
# 試験的にhttps通信(CONNECT)を有効化
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
#6. きっとエラーは発生します
#7. 自己責任で使ってください
 
#use
use strict;
 
use utf8;
use POSIX;
 
use Encode 'encode';
use File::Basename qw(dirname basename);
use Getopt::Long qw(:config posix_default no_ignore_case gnu_compat);
use HTTP::Daemon;
use IO::Compress::Gzip qw(gzip $GzipError);
use LWP::Protocol::https;
use LWP::UserAgent;
use URI;
use threads;
use threads::shared;
use Thread::Semaphore;
 
#定数の宣言(実質的なコンフィグファイル)
my $PROXY_CONFIG  = {
  PROXY_CONFIG_FILE => '',                            #コンフィグファイル
  DEDICATED_BROWSER => "JD",                          #使用している専ブラの名前
                                                      #スクレイピング時にRangeを使う場合は必須
  DAT_DIRECTORY => "$ENV{HOME}/.jd/",                 #datファイルが置いてあるディレクトリ、最後の/はつけた方が良い
                                                      #datへのアクセスにRangeヘッダーがあった際に
                                                      #ローカルにあるdatへアクセスするのに必要
  LISTEN_HOST => "localhost",                         #listenするホスト、ipv4に強制するなら"127.0.0.1"
  LISTEN_PORT => 8080,                                #listenするポート
  FORWARD_PROXY => '',                                #上位プロクシがあれば"http://host:port/"みたいに書く
  MAXIMUM_CONNECTIONS => 20,                          #最大同時接続数
  USER_AGENT => 'Mozilla/5.0 (X11; Linux x86_64; rv:36.0) Gecko/20100101 Firefox/36.0',
  #USER_AGENT => '',
                                                      #UA偽装
  ENABLE_WEB_SCRAPING => 1,                           #datへのアクセスの際にWEBスクレイピングを有効にする
                                                      #datへの直アクセスが禁止されない限りは有効にしない方がいい
                                                      #0で無効、1で有効
  ENABLE_PARTIAL_CONTENT => 1,                        #ENABLE_WEB_SCRAPINGが有効な状態で
                                                      #datへのアクセスにRnageヘッダーが含まれていた場合に
                                                      #206で応答するようにする(EXPERIMENTAL)
                                                      #0で無効、1で有効
  ENABLE_MEMORY_CACHE => 1,                           #メモリ上でdatの取得したサイズ、最新のレスの番号と内容をキャッシュする(EXPERIMENTAL)
                                                      #0で無効、1で有効
  TIMEOUT => 9,                                       #接続のタイムアウト値
                                                      #専ブラのタイムアウト値より小さい値にした方が良い
  DISABLE_TE_HEADER => 1,                             #If-Modified-Sinceヘッダーのない要求がプロクシに来た場合に
                                                      #TEヘッダーが付加されるのを止めるかどうか
                                                      #0で無効、1で有効
  ENABLE_SSL_CONNECTION => 1,                         #https通信を有効にする、動くには動くが
                                                      #しっかりした処理ではないので通信内容が壊れるかもしれない
                                                      #0で無効、1で有効
  TCP_CONNECTION_BUFFER => 8192,                      #tcpレベルで通信する時のバッファーの最大bytes数
  KEEP_COOKIE => 1,                                   #このプロクシで*.2ch.net、*.bbspink.comのcookieを保持するかどうかのフラグ
                                                      #0で無効、1で有効
  UNIQ_COOKIE => 0,                                   #KEEP_COOKIEが有効になっている状態で
                                                      #書き込み毎にcookieを変えたい場合はこれを有効にする
                                                      #0で無効、1で有効
  HANDLED_COOKIES => [qw(__cfduid yuki PREN)],        #プロクシで保持するクッキー
  DAT_URL => '^http://([\w]+)(\.2ch\.net|\.bbspink\.com)(:[\d]+)?/([\w]+)/(?:dat|kako/\d+(?:/\d+)?)/([\d]+)\.dat(\.gz)?$',  #datへのアクセスかを判定する正規表現
  NULL_DEVICE => '/dev/null',                         #nullデバイスの場所
  PID_FILE_NAME => "/tmp/2chproxy.pid",               #pidが書かれたファイル、2重起動禁止にも用いている
  LOG_FILE_NAME => "/tmp/2chproxy.log",               #ログファイル
  NULL_DEVICE_WIN32 => 'nul',                         #nullデバイスの場所(Windows)
  PID_FILE_NAME_WIN32 => dirname($0)."/2chproxy.pid", #pidが書かれたファイル、2重起動禁止にも用いている(Windows)
  LOG_FILE_NAME_WIN32 => dirname($0)."/2chproxy.log", #ログファイル(Windows)
  LOG_LEVEL => 5,                                     #ログ出力の閾値
  #以下WEBスクレイピングの際の正規表現
  TITLE_REGEX => '^<title>(.*)</title>$',             #タイトル抽出
  #                       1.レス番                         2.目欄             3.名前/ハッシュ           4.日付|ID                 5.BE1           6.BE2          7.本文
  RESPONSE_REGEX  => '^<dt>(\d+)\s[^<]*<(?:a href="mailto:([^"]+)"|font[^>]*)><b>(.*?)</b></(?:a|font)>.([^<]+?)\s?(?:<a [^>]*be\((\d+)\)[^>]*>\?([^<]+)</a>)?<dd>(.+)'
  #WEBスクレイピングの細かい部分の正規表現は下の方
};
 
#ログ出力用、こっちは弄らないでね
use constant {
  LOG_DEBUG => 7,
  LOG_INFO => 6,
  LOG_NOTICE => 5,
  LOG_WARN => 4,
  LOG_ERR => 3
};
 
#グローバル変数の宣言
my $log_level = $PROXY_CONFIG->{LOG_LEVEL};
my $null_device;
my $pid_file_name;
my $log_file_name;
my $charcode;
my ($is_daemon, $help, $kill_process, $settings, $verbose);
my $UA;
my $dedicated_browser;
my $dat_directory;
my %cookie :shared;
my %mem_cache_dat_last_str  :shared;
my %mem_cache_dat_last_num  :shared;
my %mem_cache_dat_length  :shared;
my $semaphore;
my $tcp_connection_buffer;
 
#グローバル変数の初期化
sub initialize_global_var() {
  $log_level = $PROXY_CONFIG->{LOG_LEVEL};
  #ログレベルの変更
  if ($verbose) {
    $log_level = 6;
  }
  $null_device = ($^O !~ m|MSWin32|i) ? $PROXY_CONFIG->{NULL_DEVICE} : $PROXY_CONFIG->{NULL_DEVICE_WIN32};
  $pid_file_name = ($^O !~ m|MSWin32|i) ? $PROXY_CONFIG->{PID_FILE_NAME} : $PROXY_CONFIG->{PID_FILE_NAME_WIN32};
  $log_file_name = ($^O !~ m|MSWin32|i) ? $PROXY_CONFIG->{LOG_FILE_NAME} : $PROXY_CONFIG->{LOG_FILE_NAME_WIN32};
 
  $charcode  = "UTF-8";
  #とりあえずWindowsだけcp932で出力
  if ($^O =~ m/MSWin32/) {
    $charcode = "cp932";
  }
  $UA  = LWP::UserAgent->new();
  $dedicated_browser = $PROXY_CONFIG->{DEDICATED_BROWSER};
  $dat_directory = ($PROXY_CONFIG->{DAT_DIRECTORY} =~ m|/$|) ? $PROXY_CONFIG->{DAT_DIRECTORY} : $PROXY_CONFIG->{DAT_DIRECTORY}."/";
  $tcp_connection_buffer = ($PROXY_CONFIG->{TCP_CONNECTION_BUFFER} > 0) ? $PROXY_CONFIG->{TCP_CONNECTION_BUFFER} : 8192;
  #タイムアウト値を設定
  $UA->timeout($PROXY_CONFIG->{TIMEOUT});
  #上位プロクシの設定(FORWARD_PROXY(http,httpsのみ)、環境変数)
  #優先順位はFORWARD_PROXY > 環境変数
  $UA->env_proxy();
  if ($PROXY_CONFIG->{FORWARD_PROXY}) {
    $UA->proxy([qw(http https)], $PROXY_CONFIG->{FORWARD_PROXY});
  }
  #TEヘッダーの付加をしないように設定する
  if ($PROXY_CONFIG->{DISABLE_TE_HEADER}) {
    push(@LWP::Protocol::http::EXTRA_SOCK_OPTS, SendTE => 0);
  }
  else {
    push(@LWP::Protocol::http::EXTRA_SOCK_OPTS, SendTE => 1);
  }
  #セマフォの設定
  if ($PROXY_CONFIG->{MAXIMUM_CONNECTIONS} > 1) {
    $semaphore  = Thread::Semaphore->new($PROXY_CONFIG->{MAXIMUM_CONNECTIONS});
  }
  else {
    $semaphore  = Thread::Semaphore->new(1);
  }
}
 
sub print_log() {
  my $level  = shift;
  my @args = @_;
  if ($level <= $log_level) {
    print Encode::encode($charcode, join("", @args));
  }
  return 0;
}
 
#help
sub help() {
  print encode($charcode,
        "Usage: 2chproxy [options]\n".
        "\tWebスクレイピングも一応出来るプロクシ。\n".
        "\tLinuxでJD使ってる人用だけど他のでも動くかも。\n".
        "\tこのプロクシはユーザーが保存しているdatファイルを\n".
        "\t読みにいこうとするので一般ユーザー以外での起動は\n".
        "\tあまりおすすめしない。\n".
        "\tまた、その場合はRangeヘッダーに対応できないので注意。\n".
        "\tOption:\n".
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
        "\t\t\tその時はrm ".$pid_file_name."してくれれば大丈夫なはず。\n"
      );
  exit 0;
}
 
sub settings() {
  #stub
}
 
#コマンドラインの取得
sub getopt() {
  GetOptions(
    "daemon|d" => \$is_daemon,
    "help|h" => \$help,
    "kill|k" => \$kill_process,
    "settings|s" => \$settings,
    "verbose|v" => \$verbose
  );
}
 
#既にプロクシが起動しているか
#戻り値:
# 起動している:プロクシのpid
# 起動していない:0
sub is_running() {
  my $lock_file;
  if (open ($lock_file, "<", $pid_file_name)) {
    my $pid;
    if (read($lock_file, $pid, -s $pid_file_name)) {
      &print_log(LOG_INFO, "pid: ".$pid."\n");
      return $pid+0;
    }
    close ($lock_file);
  }
  undef $lock_file;
  return 0;
}
 
#起動中のプロクシを殺す
sub kill() {
  my $pid = $_[0];
  if ("$pid" =~ m|^[\d]+$|) {
    &print_log(LOG_INFO, "kill process: ".$pid."\n");
    kill('INT', $pid+0);
  }
  else {
    &print_log(LOG_DEBUG, "illegal pid: ".$pid."\n");
  }
}
 
#シグナルへの対処
sub set_signal() {
  $SIG{PIPE}  = sub {
    &print_log(LOG_NOTICE, "Broken pipe\n");
  };
  $SIG{INT} = sub {
    unlink $pid_file_name;
    exit 0;
  };
  $SIG{TERM}  = sub {
    unlink $pid_file_name;
    exit 0;
  };
}
 
#デーモン化(*nix向け?)
#そこそこちゃんと作ったけど
#少なくともWinだとうまく動作しない
#start-stop-daemonとかdaemonとか
#そういうものが使える人はそっちを使った方がいいと思う
sub demonize() {
  fork() and exit 0;
  POSIX::setsid();
  fork() and exit 0;
  umask 0;
  chdir '/';
  open(STDIN, '<', $null_device) or die;
  open(STDOUT, '>', $log_file_name) or die;
  open(STDERR, '>', $log_file_name) or die;
  return 0;
}
 
#pidの書き込み
sub exclusive_lock() {
  my $lock_file;
  open ($lock_file, ">", $pid_file_name) or die "cannot open pid file: ".$pid_file_name."\n";
  print $lock_file $$;
  close ($lock_file);
  undef $lock_file;
}
 
sub html2dat() {
  my $html  = $_[0];
  my $title = 0;
  my @dat;
  my $res_del_tail_br = '<br><br>';                                     #末尾の<br> <br>を消す
  my $res_del_a = '<a\shref=[^>]+>([^&][^<]*)</a>';                     #安価以外のリンクを消す
  my $res_del_img = '<img\s*src="http://(img\.2ch\.net/[^"]*)"\s*/?>';  #BEの絵文字をsssp://に
 
  foreach my $line (split(/\n/, $html)) {
    chomp $line;
    &print_log(LOG_DEBUG, $line."\n");
    if (!$title) {
      if ($line =~ m/$PROXY_CONFIG->{TITLE_REGEX}/) {
        $line =~ s|$PROXY_CONFIG->{TITLE_REGEX}|$1|g;
        $title  = $line;
        &print_log(LOG_INFO, $title."\n");
      }
      next;
    }
    &print_log(LOG_DEBUG, "line\n");
    if ($line =~ m/$PROXY_CONFIG->{RESPONSE_REGEX}/) {
      my $res_number;
      $res_number = $1+0;
      &print_log(LOG_DEBUG, "res_number: ".$res_number."\n");
      $line = "$3<>$2<>$4 $5<>$6<>";
      if ($5 && $6) {
        $line = "$3<>$2<>$4 BE:$5-$6<>$7<>";
      }
      else {
        $line = "$3<>$2<>$4<>$7<>";
      }
      $line =~ s|$res_del_tail_br||g;
      $line =~ s|$res_del_a|$1|g;
      $line =~ s|$res_del_img|sssp://$1|g;
      if ($res_number == 1) {
        $line .= $title;
      }
      &print_log(LOG_DEBUG, $line."\n");
      push(@dat, $line);
    }
  }
  return @dat;
}
 
#保持しているcookieをスカラーの文字列で返す
sub get_cookie() {
  my ($domain)  = @_;
  my @cookie_array;
  &print_log(LOG_INFO, 'set cookie for '.$domain."\n");
  foreach my $key (@{$PROXY_CONFIG->{HANDLED_COOKIES}}) {
    lock(%cookie);
    if ($cookie{$domain.'@'.$key}) {
      &print_log(LOG_INFO, 'add cookie: '.$key."\n");
      push(@cookie_array, $key.'='.$cookie{$domain.'@'.$key});
    }
  }
  &print_log(LOG_INFO, 'cookie_array: '.($#cookie_array+1)."\n");
  #cookieが存在しない場合はundefを返す
  if ($#cookie_array == -1) {
    return undef;
  }
  return join("; ", @cookie_array);
}
 
#Cookieヘッダーの配列からCookieを取り出す
sub extract_cookie() {
  my @headers  = @_;
  my %cookie_args;
  my $domain;
  foreach my $header (@headers) {
    foreach my $cookie_arg (split(/;/, $header)) {
      my ($key, $value) = split(/=/, $cookie_arg);
      #先頭の空白を削除
      $key  =~ s|^\s*||;
      $cookie_args{$key}  = $value;
    }
  }
  $domain = $cookie_args{"domain"};
  &print_log(LOG_INFO, 'extract cookies from '.$domain."\n");
  foreach my $key (@{$PROXY_CONFIG->{HANDLED_COOKIES}}) {
    if ($cookie_args{$key}) {
      &print_log(LOG_INFO, 'cookie found: '.$key."\n");
      lock(%cookie);
      $cookie{$domain.'@'.$key} = $cookie_args{$key};
    }
    else {
      &print_log(LOG_INFO, 'cookie not found: '.$key."\n");
    }
  }
  #特定条件下では保持しているクッキーを削除する
  if ($PROXY_CONFIG->{UNIQ_COOKIE}) {
    lock(%cookie);
    if ($cookie{$domain.'@'.'PREN'}) {
      undef %cookie;
    }
  }
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
    &print_log(LOG_INFO, "no match type of 専ブラ: ".$dedicated_browser.".\n")
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
  undef $file;
  #ギコナビのみ改行コードがCRLFになっているので直す
  if ($dedicated_browser =~ m|^gikoNavi|i) {
    $content =~ s|\r\n|\n|g;
  }
  return $content;
}
 
#tcpレベルでの通信部分
sub tcp_connection() {
  my ($client, $server) = @_;
  #変更前の値を保存
  my $c_autoflush = $client->autoflush;
  my $c_blocking  = $client->blocking;
  my $s_autoflush = $server->autoflush;
  my $s_blocking  = $server->blocking;
  &print_log(LOG_DEBUG, "c_autoflush: ".$c_autoflush."\n");
  &print_log(LOG_DEBUG, "c_blocking: ".$c_blocking."\n");
  &print_log(LOG_DEBUG, "s_autoflush: ".$s_autoflush."\n");
  &print_log(LOG_DEBUG, "s_blocking: ".$s_blocking."\n");
  #自動でflushさせる、ブロッキングしない
  $client->autoflush(1);
  $client->blocking(0);
  $server->autoflush(1);
  $server->blocking(0);
  my $buffer;   #送受信のバッファー
  my $rbits;    #select(2)で使う、ファイルディスクリプタ(fd)を添字としたビット配列?
  my $wbits;    #select(2)で使うかもしれない
  my $rlen;     #読み込んだバッファーの長さ
  my $wlen;     #書き込んだバッファーの長さ
  while(1) {
    #select(2)の準備
    vec($rbits, fileno($client), 1)  = 1;
    vec($rbits, fileno($server), 1)  = 1;
    #TIMEOUT秒待つ
    select($rbits, undef, undef, $PROXY_CONFIG->{TIMEOUT});
    #クライアント側のfdが読み込み可能な状態であれば読み込みに行く
    if (vec($rbits, fileno($client), 1)) {
      $rlen = 0;
      #デッドロックを考慮していないので結構危険
      while (sysread($client, $buffer, $tcp_connection_buffer)) {
        $rlen = length($buffer);
        &print_log(LOG_DEBUG, "client read: ".$rlen."bytes\n");
        $wlen = syswrite($server, $buffer, $rlen);
        &print_log(LOG_DEBUG, "socket write: ".$wlen."bytes\n");
      }
      &print_log(LOG_DEBUG, "client read finished\n");
      #読み込み可能にもかかわらず読み込むbyte列が無い場合は
      #送るデータがないものとみなして通信を終了する
      if (!$rlen) {
        last;
      }
    }
    else {
      &print_log(LOG_DEBUG, "client can't read\n");
    }
    #サーバー側のfdが読み込み可能な状態であれば読み込みに行く
    if (vec($rbits, fileno($server), 1)) {
      $rlen = 0;
      #デッドロックを考慮していないので結構危険
      while (sysread($server, $buffer, $tcp_connection_buffer)) {
        $rlen = length($buffer);
        &print_log(LOG_DEBUG, "server read: ".$rlen."bytes\n");
        $wlen = syswrite($client, $buffer, $rlen);
        &print_log(LOG_DEBUG, "client write: ".$wlen."bytes\n");
      }
      &print_log(LOG_DEBUG, "server read finished\n");
      #読み込み可能にもかかわらず読み込むbyte列が無い場合は
      #送るデータがないものとみなして通信を終了する
      if (!$rlen) {
        last;
      }
    }
    else {
      &print_log(LOG_DEBUG, "server can't read\n");
    }
  }
  #ソケットのautoflushとblockingを元の値に戻す(どうせこの後closeするしいらない処理?)
  $client->autoflush($c_autoflush);
  $client->blocking($c_blocking);
  $server->autoflush($s_autoflush);
  $server->blocking($s_blocking);
}
 
#httpsな通信
sub ssl_connection() {
  my ($ref_client, $ref_request, $dport)  = @_;
  my $client  = $$ref_client;
  my $request = $$ref_request;
  my $uri = $request->uri;
  #CONNECTメソッドなので繋ぐだけ
  my $socket  = IO::Socket::INET->new(
    PeerAddr => $uri->host,
    PeerPort => $dport,
    Proto => 'tcp'
  ) or return 'connection failed';
  #クライアントへ200 Connection establishedを返す
  &print_log(LOG_INFO, "return connection established\n");
  my $str_connection_established  = $request->protocol." 200 Connection established\r\n\r\n";
  syswrite($client, $str_connection_established, length($str_connection_established));
  #通信の中身を見ずにtcpレベルで通信させる
  &tcp_connection($client, $socket);
  &print_log(LOG_INFO, "finished ssl connection\n");
  #$clientはconnection()側で処理するのでこちら側ではcloseしない
  close($socket);
  return undef;
}
 
#通信部分
sub connection() {
  my $client  = $_[0];
  $semaphore->down(1);
  &print_log(LOG_INFO, "start connection.\n");
  while (my $request  = $client->get_request()) {
    #接続先の表示
    &print_log(LOG_INFO, $client->sockhost." : ".$request->method." ".$request->uri->as_string()."\n");
    &print_log(LOG_DEBUG, $request->headers_as_string."\n");
    my $uri = $request->uri;
    my $dport;
    if ($uri->as_string =~ m|^http://[^/]*(?::(\d+))|) {
      $dport  = $1;
      &print_log(LOG_INFO, "destination port is ".$dport."\n");
    }
 
    if ($PROXY_CONFIG->{ENABLE_SSL_CONNECTION} && $dport == 443 && $request->method eq 'CONNECT') {
      my $err = &ssl_connection(\$client, \$request, $dport);
      if ($err) {
        &print_log(LOG_INFO, $err."\n");
      }
      last;
    }
 
    #一部のドメインへの接続はUAとクッキーを変更する
    if ($uri->host =~ m@(\.2ch\.net|\.bbspink\.com)$@) {
      my $domain  = $1;
      if ($PROXY_CONFIG->{USER_AGENT}) {
        &print_log(LOG_INFO, 'change user-agent:'.$request->header('User-Agent')."->".$PROXY_CONFIG->{USER_AGENT}."\n");
        $request->header('User-Agent' => $PROXY_CONFIG->{USER_AGENT});
      }
      #クッキーが専ブラによって指定されていない場合は設定する
      if ($PROXY_CONFIG->{KEEP_COOKIE}) {
        my $cookie_str  = &get_cookie($domain);
        if ($cookie_str) {
          if ($request->header('Cookie')) {
            $cookie_str = $request->header('Cookie')."; ".$cookie_str;
          }
          &print_log(LOG_INFO, 'Cookie: '.$cookie_str."\n");
          $request->header('Cookie' => $cookie_str);
        }
      }
    }
 
    #ウェブスクレイピングが無効かdat又は
    #ホスト名がheadlineなドメインについてはあまり何もせずに返す
    #ただし、一部ドメインに対してはクッキーを保存する
    if (!$PROXY_CONFIG->{ENABLE_WEB_SCRAPING} || ( ($uri->as_string !~ m|$PROXY_CONFIG->{DAT_URL}|) || ($1 eq 'headline') ) ) {
      my $sent_headers  = 0;
      my $chunked = 0;
      my $response  = $UA->simple_request($request,
        #ここの関数内で受信したデータをクライアントへ逐次送信する
        sub {
          my ($chunk_data, $res, $proto) = @_;  #受信した部分的なコンテンツ、この通信のHTTP::Responseオブジェクト、何か
          my $wlen;                             #ソケットに書き込んだ長さ
          #クライアントへHTTPステータスとヘッダーを送っていない場合は送る
          if (!$sent_headers) {
            #受信したものにContent-Lengthヘッダーが存在しない場合は
            #クライアントにchunked形式で返す
            if (!$res->header('Content-Length')) {
              &print_log(LOG_INFO, "chunked detected, content return as chunked\n");
              $chunked  = 1;
              $res->header('Transfer-Encoding' => 'chunked');
            }
            else {
              &print_log(LOG_INFO, "Content-Length: ".$res->header('Content-Length')."\n");
            }
            #Client-*なヘッダーを削除
            #特にClient-Transfer-Encodingは必ず削除する
            #(JDはClient-Transfer-Encoding: chunkedがあるとchunked形式と判断しているような動作をするため)
            foreach my $header (qw(Client-Peer Client-Response-Num Client-Transfer-Encoding)) {
              if ($res->header($header)) {
                $res->remove_header($header);
              }
            }
            #"\r\n"の指定はした方が良い
            my $header = $res->as_string("\r\n");
            &print_log(LOG_DEBUG, $header);
            syswrite($client, $header, length($header));
            $sent_headers = 1;
          }
          #コンテンツの部分はchunked形式で返すか否かで送信方法を分ける
          if ($chunked) {
            &print_log(LOG_DEBUG, sprintf("%x", length($chunk_data))."\r\n");
            syswrite($client, sprintf("%x", length($chunk_data))."\r\n");
            syswrite($client, $chunk_data."\r\n");
          }
          else {
            syswrite($client, $chunk_data, length($chunk_data));
          }
        }
      );
      #一部ドメインへの接続はクッキーを保存する
      if ($uri->host =~ m@(\.2ch\.net|\.bbspink\.com)$@) {
        if ($PROXY_CONFIG->{KEEP_COOKIE} && $response->header('Set-Cookie')) {
          &print_log(LOG_INFO, "Set-Cookie header found\n");
          &extract_cookie($response->header('Set-Cookie'));
        }
      }
      #chunked形式の場合はコールバック内でフッターが送れないのでここで送る
      if ($chunked) {
        &print_log(LOG_DEBUG, "0\r\n\r\n");
        syswrite($client, "0\r\n\r\n");
      }
      # HEADリクエストと20x以外の応答(要はコンテンツの無いレスポンス)と
      # Content-Lengthが0な20x応答は
      # 上のコールバックが呼ばれないのでこちらで処理する
      # if ( ($request->method eq 'HEAD') || (!$response->is_success) ) {
      #上のコールバックが呼ばれない->コールバック内でヘッダー周りを処理出来ていないのとほぼ同等なので
      #シンプルなこちらを分岐に使う
      elsif (!$sent_headers) {
        $client->send_response($response);
      }
      &print_log(LOG_INFO, $response->status_line."\n");
      next;
    }
 
    my $last_res;         #リクエストされたURIに対するメモリ上のキャッシュ/ローカルのdatファイルの中で最新のレス
    my $host  = $1;
    my $domain  = $2;
    my $category  = $4;
    my $dat = $5;
    my $is_gzip = $6;
    #URLをハッシュのキーにしようと思ったけど一部板で
    #host名が違っても同じデータを寄越すものがあったので
    #(kilauea.bbspink.comとaoi.bbspink.com、他にも板移転があった場合?)
    #ドメイン、カテゴリ、datの3つをハッシュのキーに設定
    my $hash_key  = $2.$4.$5;
    my $rewrite_uri  = "http://".$host.$domain."/test/read.cgi/".$category."/".$dat."/";
    my $range;
    my $expected_partial_content;
    my $expected_head_response;
    #HEADでdatが更新されたかのみを確認する場合は
    #レスポンスからコンテンツを取り除く
    if ($request->method eq 'HEAD') {
      &print_log(LOG_INFO, 'change method: '.'HEAD'.'->'.'GET'."\n");
      $expected_head_response = 1;
      $request->method('GET');
    }
    #スクレイピング時にENABLE_PARTIAL_CONTENTを有効にしていれば
    #Rangeヘッダーを見に行って差分取得を行う
    if ($PROXY_CONFIG->{ENABLE_PARTIAL_CONTENT} && $request->header('Range') =~ m|^bytes=(\d+)-$|) {
      $range  = $1;
      &print_log(LOG_INFO, 'Range header found: '.$range.'-'."\n");
      #メモリ上のキャッシュに前回のアクセス時のものがあればそれを利用
      if ($PROXY_CONFIG->{ENABLE_MEMORY_CACHE}) {
        {
          lock(%mem_cache_dat_last_num);
          lock(%mem_cache_dat_last_str);
          lock(%mem_cache_dat_length);
          if ($mem_cache_dat_last_num{$hash_key} && $mem_cache_dat_last_str{$hash_key} && $mem_cache_dat_length{$hash_key}) {
            $last_res = $mem_cache_dat_last_str{$hash_key};
            &print_log(LOG_INFO, "cache found, last res: ".$last_res."\n");
            $rewrite_uri  .= $mem_cache_dat_last_num{$hash_key}."n-";
          }
          else {
            &print_log(LOG_INFO, "cache not found, try to read local dat file\n");
          }
        }
      }
      #無い場合はローカルのdatファイルからの読み込みを試みる
      if (!$last_res) {
        my $local_dat_file_name = &get_local_dat_path($host, $domain, $category, $dat);
        &print_log(LOG_INFO, 'dat file path: '.$local_dat_file_name."\n");
        my $local_dat_size;
        my $local_dat_content = &get_local_dat_content($local_dat_file_name);
        if ($local_dat_content) {
          my @local_dat_content_array = split(/\n/, $local_dat_content);
          if ($#local_dat_content_array > 0) {
            {
              lock(%mem_cache_dat_last_num);
              lock(%mem_cache_dat_last_str);
              lock(%mem_cache_dat_length);
              $mem_cache_dat_last_num{$hash_key}  = $#local_dat_content_array+1;
              $rewrite_uri  .= $mem_cache_dat_last_num{$hash_key}."n-";
              #内部文字列で保持しておきたいので内部文字列にデコード
              $mem_cache_dat_last_str{$hash_key}  = Encode::decode('cp932', $local_dat_content_array[$#local_dat_content_array]);
              $last_res = $mem_cache_dat_last_str{$hash_key};
              $mem_cache_dat_length{$hash_key}  = length($local_dat_content);
              &print_log(LOG_INFO, "local dat length: ".$mem_cache_dat_length{$hash_key}."\n");
            }
            &print_log(LOG_INFO, "local dat found, last res: ".$last_res."\n");
          }
        }
      }
      #メモリ上にもローカルにも差分取得のための情報が無い場合は
      #全レス取得してそこからRangeの該当部分を返す
      if (!$last_res) {
        $expected_partial_content = 1;
      }
      else {
        #レス数が1001に到達している場合は304を返す
        my $response;
        {
          lock(%mem_cache_dat_last_num);
          if ($mem_cache_dat_last_num{$hash_key} >= 1001) {
            &print_log(LOG_INFO, 'this thread already reached '.(1001)."\n");
            $response = HTTP::Response->new(304, 'Not Modified');
          }
        }
        if ($response) {
          $client->send_response($response);
          next;
        }
      }
    }
    &print_log(LOG_INFO, 'rewrite_uri: '.$rewrite_uri."\n");
    $request->uri($rewrite_uri);
 
    #416を応答されないようにRangeヘッダーを削除
    if ($request->header('Range')) {
      $request->remove_header('Range');
    }
 
    my $response  = $UA->simple_request($request);
    &print_log(LOG_INFO, "response: ".$response->status_line."\n");
 
    #忘れぬ内にクッキーの保存
    if ($PROXY_CONFIG->{KEEP_COOKIE} && $response->header('Set-Cookie')) {
      &print_log(LOG_INFO, "Set-Cookie header found\n");
      &extract_cookie($response->header('Set-Cookie'));
    }
 
    #20x以外の応答は何もせずにクライアントへ返す
    if (!$response->is_success()) {
      &print_log(LOG_NOTICE, "Server didn't return 20x\n");
      $client->send_response($response);
      next;
    }
 
    #Last-Modifiedヘッダーが無い場合は
    #Dateヘッダーの値をコピーする
    if (!$response->header('Last-Modified')) {
      &print_log(LOG_INFO, "add Last-Modified header\n");
      $response->header('Last-Modified' => $response->header('Date'));
    }
    #Dateがダブっているので片方削除
    $response->remove_header('Date');
 
    &print_log(LOG_INFO, "convert html to dat\n");
    my @content_array  = &html2dat($response->decoded_content(charset => 'cp932'));
    &print_log(LOG_INFO, "size of content_array: ".($#content_array+1)."\n");
 
    #chunkedは消毒だー
    if (defined($response->header("Transfer-Encoding"))) {
      &print_log(LOG_INFO, "Transfer-Encoding defined.\n");
      $response->remove_header("Transfer-Encoding");
    }
    if (defined($response->header("Client-Transfer-Encoding"))) {
      &print_log(LOG_INFO, "Client-Transfer-Encoding defined.\n");
      $response->remove_header("Client-Transfer-Encoding");
    }
 
    my $content;
    #last_resが存在する==クライアントには206を返すべきである
    if ($last_res) {
      my $first_res;          #デバッグ用、受信した中で最初のレス
      #取得レス数が一個なら
      #更新していないので304を返す
      if ($#content_array == 0) {
        &print_log(LOG_INFO, "content not modified\n");
        $response = HTTP::Response->new(304, 'Not Modified');
        $client->send_response($response);
        next;
      }
      #更新が存在する場合は前回通信時での最新のレスと
      #今回通信時の最初のレスが一致していれば206を返す
      elsif ($last_res eq ($first_res = shift(@content_array))) {
        {
          lock(%mem_cache_dat_length);
          #Rangeの値として不適切(というかクライアント側でファイルが壊れている云々と言うはず)
          #なので416を返す
          if ($range > $mem_cache_dat_length{$hash_key}) {
            &print_log(LOG_NOTICE, 'invalid range: '.$range."\n");
            &print_log(LOG_NOTICE, 'dat length: '.$mem_cache_dat_length{$hash_key}."\n");
            $response = HTTP::Response->new(416, 'Requested Range Not Satisfiable');
            $client->send_response($response);
            #メモリのキャッシュを削除
            {
              lock(%mem_cache_dat_last_num);
              $mem_cache_dat_last_num{$hash_key}  = undef;
            }
            {
              lock(%mem_cache_dat_last_str);
              $mem_cache_dat_last_str{$hash_key}  = undef;
            }
            {
              lock(%mem_cache_dat_length);
              $mem_cache_dat_length{$hash_key}  = undef;
            }
            next;
          }
          #rangeの方が小さい時(専ブラがエラー検出を行おうとしている時)は
          #その分だけ前回の最新のレスからコピーする
          #前回の最新のレスより大きなbyte数でエラー検出を行おうとしている場合は
          #*未定義*
          #(多分クライアントが"ファイルが壊れている"と言うはず)
          elsif ($range < $mem_cache_dat_length{$hash_key}) {
            my $error_detection  = Encode::encode('cp932', $last_res."\n");
            $content  = substr($error_detection, $range-$mem_cache_dat_length{$hash_key});
          }
          $content  .= Encode::encode('cp932', join("\n", @content_array)."\n");
          #差分を取得した分だけメモリのキャッシュを更新する
          #ただし更新チェックのみ(methodがHEADなリクエスト)だった場合は更新しない
          if (!$expected_head_response) {
            {
              lock(%mem_cache_dat_last_num);
              $mem_cache_dat_last_num{$hash_key}  += $#content_array +1;
            }
            {
              lock(%mem_cache_dat_last_str);
              $mem_cache_dat_last_str{$hash_key}  = pop(@content_array);
            }
            {
              lock(%mem_cache_dat_length);
              $mem_cache_dat_length{$hash_key}  = $range+length($content);
            }
          }
        }
        &print_log(LOG_INFO, "content returned as partial content\n");
        $response->code(206);
        $response->message('Partial Content');
        #206用のヘッダーを追加
        $response->header('Accept-Range' => 'bytes');
        &print_log(LOG_INFO, 'add header Content-Range: '.'bytes '.$range.'-'.($range+length($content)-1).'/'.($range+length($content))."\n");
        $response->header('Content-Range' => 'bytes '.$range.'-'.($range+length($content)-1).'/'.($range+length($content)));
      }
      #レスが一致していないので416を返す
      else {
        &print_log(LOG_NOTICE, "responses don't match\n");
        &print_log(LOG_INFO, "last  res: ".$last_res."\n");
        &print_log(LOG_INFO, "first res: ".$first_res."\n");
        $response = HTTP::Response->new(416, 'Requested Range Not Satisfiable');
        $client->send_response($response);
        #メモリのキャッシュを削除する
        {
          lock(%mem_cache_dat_last_num);
          $mem_cache_dat_last_num{$hash_key}  = undef;
        }
        {
          lock(%mem_cache_dat_last_str);
          $mem_cache_dat_last_str{$hash_key}  = undef;
        }
        {
          lock(%mem_cache_dat_length);
          $mem_cache_dat_length{$hash_key}  = undef;
        }
        next;
      }
    }
    #全レス取得時
    else {
      #html2datでの変換に失敗、または2ch側がエラーを返してきた
      #(datが見つかりません的なもの)場合は302を返す
      #info.2ch.net/index.php/Monazilla/develop/dat#未稿によれば
      #302になる度.dat->kako.dat.gz->kako.dat[->offlaw.cgi]の順に使用
      if (!@content_array || !$content_array[0]) {
        &print_log(LOG_NOTICE, "content not found, returned as 302\n");
        $response = HTTP::Response->new(302, 'Found');
        #元のuriから次にLocationとして設定すべきuriを生成するのが面倒なので
        #人大杉のurlを返しておく
        #上コメント内のurlを見る限りではLocationヘッダーは見ないのだと思うが
        #Locationヘッダーを見る専ブラはもしかしたらうまく過去ログ参照しないかも
        $response->header('Location' => 'http://www2.2ch.net/live.html');
        $client->send_response($response);
        next;
      }
      $content  = Encode::encode('cp932', join("\n", @content_array)."\n");
      {
        lock(%mem_cache_dat_last_num);
        $mem_cache_dat_last_num{$hash_key}  = $#content_array +1;
        &print_log(LOG_INFO, "last num: ".($#content_array+1)."\n");
      }
      {
        lock(%mem_cache_dat_last_str);
        $mem_cache_dat_last_str{$hash_key}  = pop(@content_array);
        &print_log(LOG_INFO, "last str: ".$mem_cache_dat_last_str{$hash_key}."\n");
      }
      {
        lock(%mem_cache_dat_length);
        $mem_cache_dat_length{$hash_key}  = length($content);
        &print_log(LOG_INFO, "length: ".length($content)."\n");
      }
      if ($expected_partial_content) {
        #リクエストにRangeヘッダーがあり206を返すのが期待されている場合は
        #Rangeの範囲にあわせて206,416のどちらかを返す
        if ($range < length($content)) {
          &print_log(LOG_INFO, "content returned as partial content\n");
          $content  = substr($content, $range);
          $response->code(206);
          $response->message('Partial Content');
          #206用のヘッダーを追加
          $response->header('Accept-Range' => 'bytes');
          &print_log(LOG_INFO, 'add header Content-Range: '.'bytes '.$range.'-'.($range+length($content)-1).'/'.($range+length($content))."\n");
          $response->header('Content-Range' => 'bytes '.$range.'-'.($range+length($content)-1).'/'.($range+length($content)));
        }
        #Rangeの範囲がおかしいので416を返す
        else {
          &print_log(LOG_NOTICE, 'invalid range: '.$range."\n");
          &print_log(LOG_NOTICE, 'dat length: '.$mem_cache_dat_length{$hash_key}."\n");
          $response = HTTP::Response->new(416, 'Requested Range Not Satisfiable');
          $client->send_response($response);
          #メモリのキャッシュを削除する
          {
            lock(%mem_cache_dat_last_num);
            $mem_cache_dat_last_num{$hash_key}  = undef;
          }
          {
            lock(%mem_cache_dat_last_str);
            $mem_cache_dat_last_str{$hash_key}  = undef;
          }
          {
            lock(%mem_cache_dat_length);
            $mem_cache_dat_length{$hash_key}  = undef;
          }
          next;
        }
      }
      #urlが.dat.gzだった場合はレスポンスの本体をgzipに圧縮する
      #Content-Typeをapplication/gzipにすることを忘れずに
      #過去ログはRangeが送られてこないはずなので処理部分はここだけでよいはず
      elsif ($is_gzip) {
        my $tmp;
        if (gzip \$content => \$tmp) {
          $content  = $tmp;
          $response->header('Content-Type' => 'application/gzip');
        }
        #gzip圧縮に失敗した場合は500を返す
        else {
          &print_log(LOG_ERR, $GzipError."\n");
          $response = HTTP::Response->new(500, 'Internal Server Error');
          $client->send_response($response);
          next;
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
    #クライアントに受けとったデータを流す
    $client->send_response($response);
  }
  $client->close();
  undef($client);
  &print_log(LOG_INFO, "finish connection.\n");
  $semaphore->up(1);
}
 
#
sub run_proxy() {
  my $proxy = HTTP::Daemon->new(
    LocalHost => $PROXY_CONFIG->{LISTEN_HOST},
    LocalPort => $PROXY_CONFIG->{LISTEN_PORT},
    ReuseAddr => 1  #
  ) or unlink $pid_file_name and die;
  &print_log(LOG_NOTICE, "listen to ".$proxy->url."\n");
  while (my $client = $proxy->accept()) {
    &print_log(LOG_INFO, "request received.\n");
    my $thread  = threads->new(\&connection, $client)->detach();
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
        if ($YAML->[0]{$key}) {
          $PROXY_CONFIG->{$key} = $YAML->[0]{$key};
        }
      }
      #コンフィグファイルの読み込みに成功したらグローバル変数を一新する
      &initialize_global_var();
    }
  }
}
 
#初期化処理
sub initialize() {
  #コンフィグファイルの読み込み
  &load_config();
  #2重起動しているかの確認,起動中のプロクシの制御
  my $pid = &is_running();
  if ($pid) {
    if ($kill_process) {
      &kill($pid);
      exit 0;
    }
    &print_log(LOG_ERR, basename($0)." is already running.\n");
    &print_log(LOG_ERR, "if you kill ".basename($0).", please run this command: ".basename($0)." --kill\n");
    &print_log(LOG_ERR, "or : rm ".$pid_file_name."\n");
    exit 1;
  }
  elsif ($kill_process) {
    exit 0;
  }
  #プロセスのデーモン化
  if ($is_daemon) {
    &demonize();
  }
  #シグナルの設定
  &set_signal();
  #2重起動の防止
  &exclusive_lock();
}
 
#main
{
  #グローバル変数の初期化
  &initialize_global_var();
 
  &getopt();
  if ($help) {
    &help();
    exit 0;
  }
  elsif ($settings) {
    &print_settings();
    exit 0;
  }
  &initialize();
  &run_proxy();
}
 
###   ChangeLog
#v0.1
#   初版。とりあえずスクレイピングは出来る状態
#v0.2
#   サーバーから受けとったクッキーをプロクシ側で保持して通信に使用出来るように
#v0.3
#   Webスクレイピング時のRangeへ対応、アクセスも必要な部分だけを取りに行くようにした
#   スレの更新チェック(HEAD)へ仮対応
#   eqと==を間違えるとんでもないミスを修正
#   BEがちゃんと取得出来てなかったのを修正
#   daemon化をもうちょっとまともにした
#   整合性をとるのは諦めた
#   他細々した修正ときっと増えてるバグ
#v0.4
#   ssspなgifのimgタグ周りが処理されていなかったのを修正
#   V2C/Live2ch使用時のスクレイピング時の差分取得の対応(多分)
#   スクレイピング時の差分取得のエラー検出への対応を若干強化(デフォルトでは強化前のものを使用、現状では強化の意味はなし)
#   多分増えたバグ
#v0.5
#   ギコナビでスクレイピング時の差分取得に対応
#v0.6
#   デフォルトでスクレイピングするように変更
#v0.7
#   SIGPIPEを無視するように変更
#v0.8
#   LWP::UserAgentによるTEヘッダーの挿入を抑制
#   .bbspink.comでもクッキーを保持できるようにした
#   .2ch.net、.bbspink.comへのアクセス時はUAを変更出来るようにした
#v0.9
#   Navi2chで差分取得出来るようにした
#v0.10
#   rep2(rep2スレを見るに多分rep2exの方)の差分取得に対応
#v0.11
#   差分取得に対応していない専ブラに対しては全レス取得してそこから
#   rangeに対応した部分だけ返すことで専ブラ側からは差分取得出来ているようにした
#v0.12
#   最新のレス等をキャッシュするようにした(ので実質的に全部の専ブラで差分取得出来るはず)
#   use IO::HTML;することでdecoded_contentでエラーをこっそり吐かれることがないようにした
#v0.13
#   v0.12で消えたHEADへの対応を追加
#   timeoutの値を設定できるようにした(これに起因するバグを修正するため)
#   [protocol]_proxyの環境変数に対応
#v0.13.1
#   v0.13でHEADへの対応がちゃんと出来ていなかったので修正
#v0.14
#   1001レスに達したら304を返して鯖と通信しない機能がv0.12で消えていたので修正
#   DEDICATED_BROWSER=>"rep2"が実質的にrep2ex用の設定になっていた(なってすらいなかった?)のを
#   無印rep2用の設定になるように修正
#   また、どうやらrep2(ex)の両方ともbbspink.comのdatは
#   2channelディレクトリの方に保存される*らしい*ので
#   そっちを見に行くように変更
#   rep2exを使っている人はDAT_DIRECTORYのパスの最後に"dat/"を追加する必要があるかもしれない
#v0.15
#   IO::HTMLは使わなくなっていたので削除
#   過去ログっぽいアクセスもurl書き換えの対象にした(但し正規表現は割と適当)
#   datが見つかりませんよ的なエラーが鯖から返ってきた時は302を返すようにした
#   過去ログへのアクセスのuriが.dat.gzな場合はgzipで圧縮したものをクライアントへ返すようにした
#   このため新たにIO::Compress::Gzipが追加された(コアモジュールだから何もいれなくて良い*はず*)
#v0.16
#   受信したリクエストにクッキーがある場合でKEEP_COOKIEが1ならプロクシ側で保持していたクッキーを追加するように変更
#   https通信を出来るようにした、ただし現状ではhttps通信は上位プロクシを通らないので注意
#   yamlファイルが存在した時に読み込む用にした、yamlファイルを使いたい場合にはYAML::Tinyが必要
#v0.17
#   chunkedなレスポンスはchunkedで返すように変更、画像等の大きなデータもこれで処理できるようになった*はず*
#   ssl通信でtcpレベルで通信させる部分を他のでも使えるかなーと思い関数にした、でも使わなさそう
#   yamlを読みに行くタイミングの関係で一部変数がちゃんと変わっていなかったのを修正
#   とりあえずheadlineも読み込めるようにした、DAT_URLが使われてる部分を弄っただけなので他のバージョンでも簡単に書き換え可能
#v0.17.1
#   v0.17でhelp呼びだし時に一部変数がundefになっていたのを修正
#v0.17.2
#   v0.17及びv0.17.1でContent-Lengthの値が0なレスポンス(したらば等)をクライアントへ返していない問題を修正
#   試験的にhttps通信(CONNECT)を有効化
 
#自分が把握しているバグっぽいもの
#rep2
#   書き込み後にStatus: 302 Foundという文字列が表示されてしまう
#   まちBBSのスレがうまく読み込めない?
 
#今後の予定のようなもの
#   ローカルのdatファイルのパスをリストで取得するようにするかもしれない
#   --reloadでコンフィグファイルを再読み込みするようにするかもしれない
#   CONNECTでも上位プロクシへ繋げられるようにするかもしれない
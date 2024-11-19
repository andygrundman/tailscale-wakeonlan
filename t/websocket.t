use Mojo::Base -strict;
use Mojo::JSON qw(encode_json);
use Test::More;
use Test::Mojo;

#local $ENV{MOJO_WEBSOCKET_DEBUG} = 1;

require(Mojo::File::curfile->sibling("lib/TestInit.pm"));

my $t = Test::Mojo->new(
  Mojo::File::curfile->dirname->sibling('main.pl')
);

my $a = { add_name => q{Andy},       add_mac => '00:aa:11:BB:22:cc', add_ip => '127.0.0.1' };
my $b = { add_name => q{Unpingable}, add_mac => '00:ff:22:cc:33:dd', add_ip => '192.168.0.255' };

subtest "Add 2 hosts" => sub {
  $t->post_ok("/add", form => $a)->status_is(303);
  $t->post_ok("/add", form => $b)->status_is(303);
};

## ping

subtest "ping by mac" => sub {
  $t->websocket_ok("/ws")
  ->send_ok({json => {cmd => "ping", mac => "00:aa:11:BB:22:cc"}})
  ->message_ok
  ->json_message_has("/status", "awake")
  ->finish_ok;
};

subtest "ping by ip" => sub {
  $t->websocket_ok("/ws")
  ->send_ok({json => {cmd => "ping", ip => "127.0.0.1"}})
  ->message_ok
  ->json_message_has("/status", "awake")
  ->finish_ok;
};

subtest "ping by ip with retries" => sub {
  $t->websocket_ok("/ws")
  ->send_ok({json => {cmd => "ping", ip => "192.168.0.255", retries => 1}})
  ->message_ok
  ->json_message_has("/status", "asleep")
  ->finish_ok;
};

## pingAll

subtest "pingAll" => sub {
  $t->websocket_ok("/ws")
  ->send_ok({json => {cmd => "pingAll"}})
  ->message_ok
  ->json_message_has("/status", "awake")
  ->message_ok
  ->json_message_has("/status", "awake")
  ->finish_ok;
};

## ping errors

subtest "ping unknown" => sub {
  $t->websocket_ok("/ws")
  ->send_ok({json => {cmd => "ping", mac => "00:aa:11:BB:22:ff"}})
  ->message_ok
  ->json_message_has("/error", "host not found")
  ->finish_ok;
};

subtest "no mac or ip" => sub {
  $t->websocket_ok("/ws")
  ->send_ok({json => {cmd => "ping"}})
  ->message_ok
  ->json_message_has("/error", "no mac or ip provided")
  ->finish_ok;
};

subtest "no cmd" => sub {
  $t->websocket_ok("/ws")
  ->send_ok({json => {foo => "bar"}})
  ->message_ok
  ->json_message_has("/error", "invalid command")
  ->finish_ok;
};

subtest "bad json" => sub {
  $t->websocket_ok("/ws")
  ->send_ok('{"broken":json}')
  ->message_ok
  ->json_message_has("/error", "invalid command")
  ->finish_ok;
};

done_testing();

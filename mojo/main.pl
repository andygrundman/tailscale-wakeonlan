#!/usr/bin/env -S perl -w

use Capture::Tiny ();
use Mojo::File qw(curfile path);
use Mojo::JSON qw(decode_json encode_json);
use Mojo::IOLoop;
use Mojolicious::Lite -signatures;
use Net::Ping;
use Mojo::UserAgent;
use Net::IPv4Addr ();
use Regexp::Common qw(net);

use constant DEBUG => 1;

my $config = plugin Config => {file => "main.conf"};

app->mode($config->{runtime_mode});
app->log->level($ENV{HARNESS_IS_VERBOSE} ? 'trace' : ($ENV{MOJO_LOG_LEVEL} || 'info'));
push @{app->renderer->paths}, curfile->sibling("templates");
push @{app->static->paths}, curfile->sibling("public");

# Note: the initial state of the db is created by mojo/start.sh

# main
get '/' => sub ($c) {
  _rootstash($c);
};

get '/wake' => sub ($c) {
  my $mac = lc($c->param('mac') // q{}) || do {
    return error($c, "Missing mac param");
  };

  my $host = db_host_for_mac($c, $mac);
  if (!$host) {
    $c->flash({ error_messages => [ "Unknown MAC address, please add the host first." ]});
    return $c->redirect_to("/");
  }

  my $broadcast = db_broadcast($c);
  $c->log->info("WakeOnLAN packet sent to $broadcast for $mac");
  Net::Ping::wakeonlan($mac, $broadcast);

  if ($host->{ip}) {
    # after waking, if we know the expected IP, keep trying to ping it for a bit
    $c->flash({ arisen => $host->{ip} });
  }

  return $c->redirect_to("/");
};

get '/add' => sub ($c) {
  $c->redirect_to("/");
};

post '/add' => sub ($c) {
  _rootstash($c);

  # Check if parameters have been submitted
  my $v = $c->validation;
  return $c->render('main') unless $v->has_data;

  # Validate parameters
  $v->required('add_name')->size(1, 64);
  $v->required('add_mac')->like(qr/^$RE{net}{MAC}$/);
  $v->required('add_ip')->like(qr/^$RE{net}{IPv4}$/);

  # Check if validation failed
  return $c->render('main') if $v->has_error;

  my $new_host = {
    name => $v->output->{add_name},
    mac  => lc($v->output->{add_mac}),
    ip   => $v->output->{add_ip},
  };

  $c->log->info("WakeOnLAN host added: " . encode_json($new_host));

  my $db = load_db($c);
  push @{$db->{hosts}}, $new_host;
  save_db($c, $db);

  $c->res->code(303);
  return $c->redirect_to("/");
};

get '/edit' => sub ($c) {
  $c->redirect_to("/");
};

post '/edit' => sub ($c) {
  _rootstash($c);

  my $mac = lc($c->param('mac') // q{}) || do {
    return error($c, "Missing mac param");
  };

  # Check if parameters have been submitted
  my $v = $c->validation;
  return $c->render('main') unless $v->has_data;

  # Validate parameters
  $v->required('edit_name')->size(1, 64);
  $v->required('edit_mac')->like(qr/^$RE{net}{MAC}$/);
  $v->required('edit_ip')->like(qr/^$RE{net}{IPv4}$/);

  # Check if validation failed
  return $c->render('main') if $v->has_error;

  my $new_host = {
    name => $v->output->{edit_name},
    mac  => lc($v->output->{edit_mac}),
    ip   => $v->output->{edit_ip},
  };

  $c->log->info("WakeOnLAN host edited $mac: " . encode_json($new_host));

  db_replace_mac($c, $mac, $new_host);

  $c->res->code(303);
  return $c->redirect_to("/");
};

post '/delete' => sub ($c) {
  my $mac = lc($c->param('mac') // q{}) || do {
    return $c->redirect_to("/");
  };

  my $host = db_host_for_mac($c, $mac);
  if (!$host) {
    return error($c, "Host not found");
  }

  $c->log->info("WakeOnLAN host deleted: $mac");

  db_delete_mac($c, $mac);

  $c->res->code(303);
  return $c->redirect_to("/");
};

websocket '/ws' => sub ($c) {
  $c->log->debug("New WebSocket connection");

  # Incoming message
  $c->on(message => sub ($c, $json) {
    $c->log->debug("WebSocket message: $json");
    my $req = eval { decode_json($json) };
    if ($@ || !exists $req->{cmd}) {
      return $c->send({ json => { error => "invalid command" }});
    }

    $c->inactivity_timeout(300);

    if ($req->{cmd} eq "ping") {
      my $host;
      if ($req->{mac}) {
        $host = db_host_for_mac($c, $req->{mac});
      }
      elsif ($req->{ip}) {
        $host = db_host_for_ip($c, $req->{ip});
      }
      else {
        return $c->send({ json => { error => "no mac or ip provided" }});
      }

      if ($host) {
        ping_any($c, [ $host ], $req->{tries});
      }
      else {
        return $c->send({ json => { error => "host not found" }});
      }
    }
    elsif ($req->{cmd} eq "pingAll") {
      ping_any($c, db_hosts($c));
    }
    else {
      return $c->send({ json => { error => "invalid command" }});
    }
  });
};

app->start;

###

sub ping_any {
  my ($c, $hosts, $retries_left) = @_;
  $retries_left //= 0;

  for my $host ( @{$hosts} ) {
    next unless exists $host->{ip};

    Mojo::IOLoop->subprocess->run_p(sub {
      ping_ip($c, $host);
    })->then(sub {
      my $data = shift;

      if ($data->{status} eq 'no response' && $retries_left) {
        return ping_any($c, [ $host ], --$retries_left);
      }

      $c->send({ json => $data });
    })->catch(sub {
      my $err = shift;
      $c->log->error($host->{ip} . " ping failed: $err");
    });
  }
}

sub ping_ip {
  my ($c, $host) = @_;

  my $timeout = $ENV{HARNESS_ACTIVE} ? 0.1 : 1;

  my @methods = qw(icmp udp tcp stream);
  my ($ip, $mac) = ($host->{ip}, $host->{mac});
  $c->log->debug("Pinging $ip");
  for my $method (@methods) {
    my $p = Net::Ping->new({ proto => $method, timeout => $timeout });
    my ($ret, $rtt, $ip) = $p->ping($ip);
    if ($ret) {
      return {
        ip     => $ip,
        mac    => $mac,
        status => 'awake',
        method => $method,
        ping   => sprintf("%.3f", $rtt),
      };
    }
  }

  # try syn mode as a last resort
  my $p = Net::Ping->new({ proto => "syn", timeout => $timeout });
  if ($p->ping($ip)) {
    my ($ret, $rtt, $ip) = $p->ack($ip);
    if ($ret) {
      return {
        ip     => $ip,
        mac    => $mac,
        status => 'awake',
        method => "syn",
        ping   => sprintf("%.3f", $rtt),
      };
    }
  }

  return { ip => $ip, mac => $mac, status => 'no response' };
}

sub save_db {
  my ($c, $db) = @_;
  my $file = _db_file();
  eval { $file->spew( encode_json($db) ) };
  if ($@) {
    return error($c, "JSON database corruption: $@");
  }
  return $db;
}

sub load_db {
  my $c = shift;
  my $file = _db_file();
  # json file will always be created during startup
  my $db = eval { decode_json($file->slurp) };
  if ($@) {
    return error($c, "Unable to load database: $@");
  }

  return $db;
}

sub db_hosts {
  my $db = load_db(shift);
  return $db ? $db->{hosts} : [];
}

sub db_broadcast {
  my $db = load_db(shift);
  return $db ? $db->{broadcast} : "255.255.255.255";
}

sub db_host_for_mac {
  my ($c, $mac) = @_;

  my ($host) = grep { $_->{mac} eq lc($mac) } @{ db_hosts($c) };
  return $host;
}

sub db_host_for_ip {
  my ($c, $ip) = @_;

  my ($host) = grep { $_->{ip} eq $ip } @{ db_hosts($c) };
  return $host;
}

sub db_replace_mac {
  my ($c, $old_mac, $new_host) = @_;

  # rebuild list keeping the old one's position
  my @new_list;
  for my $host ( @{ db_hosts($c) } ) {
    if ($old_mac eq $host->{mac}) {
      push @new_list, $new_host;
    }
    else {
      push @new_list, $host;
    }
  }
  my $db = load_db($c);
  $db->{hosts} = \@new_list;
  save_db($c, $db);
}

sub db_delete_mac {
  my ($c, $mac) = @_;

  my @new_list = grep { $mac ne $_->{mac} } @{ db_hosts($c) };
  my $db = load_db($c);
  $db->{hosts} = \@new_list;
  save_db($c, $db);
}

sub error {
  my ($c, $error) = @_;

  $c->flash({ error_messages => [ $error ]});
  return $c->redirect_to("/");
}

sub _rootstash {
  my $c = shift;

  my $hosts = db_hosts($c);

  # add json for use by edit form
  map { $_->{json} = encode_json($_) } @{$hosts};

  $c->stash(
    template => 'main',
    hosts    => $hosts,
  );
}

sub _db_file {
  my $file = path($config->{persist_dir});
  return $file->child("wakeonlan.json");
}

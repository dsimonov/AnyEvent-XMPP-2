#!perl
use utf8;
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::CM;
use AnyEvent::XMPP::Util qw/cmp_bare_jid/;
use JSON -convert_blessed_universally;

AnyEvent::XMPP::Test::check ('client');

print "1..2\n";

my $im = AnyEvent::XMPP::CM->new;

$im->set_accounts ($JID1 => [$PASS, { host => $HOST, port => $PORT }]);

my $c = cvreg $im, 'connected';
$c->recv;

$c = cvreg $im, 'disconnected';
$im->get_connection ($JID1)->disconnect ("test1");

my ($j, $ph, $pp, $reason, $tout) = $c->recv;

tp 1, $tout > 0, 'got timeout for next reconnect: ' . $tout;

$c = cvreg $im, 'connected';
my ($j) = $c->recv;

tp 2, cmp_bare_jid ($JID1, $j), 'reconnected alright';

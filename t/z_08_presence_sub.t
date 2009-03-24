#!perl
use utf8;
use strict;
no warnings;

use AnyEvent;
use AnyEvent::XMPP::Test;
use AnyEvent::XMPP::IM;
use AnyEvent::XMPP::Util qw/split_jid cmp_bare_jid new_iq new_message
                           new_presence bare_jid cmp_jid/;
use AnyEvent::XMPP::Node qw/simxml/;
use AnyEvent::XMPP::StanzaHandler;
use Predicates;
use JSON -convert_blessed_universally;

AnyEvent::XMPP::Test::check ('client');

print "1..4\n";

my $CV;
my $PRES;
my $IM;

my $flags = { };
my $tout;
my $ctx = pred_ctx {
   pred_decl 'start';

   pred_action start => sub {
      $IM->send (new_iq (get => src => $FJID1,
                         create => { node => { name => "query", dns => "roster" } }));
      $IM->send (new_iq (get => src => $FJID2,
                         create => { node => { name => "query", dns => "roster" } }));

      $tout = AnyEvent->timer (after => 10, cb => sub {
         my $cnt = 0;
         $IM->get_connection ($FJID1)->reg_cb (send_buffer_empty => sub {
            if (++$cnt >= 2) { $CV->send }
         });
         $IM->get_connection ($FJID2)->reg_cb (send_buffer_empty => sub {
            if (++$cnt >= 2) { $CV->send }
         });
         $PRES->send_unsubscription ($FJID1, $FJID2, 1, "Nope! NONE ANYMROE!");
         $PRES->send_unsubscription ($FJID2, $FJID1, 1, "Nope! NONE ANYMROE!");
      });

      $PRES->send_subscription_request ($FJID1, $FJID2, 1, "Hi! Lets be friends!");
   };

   pred_decl   subsc_recv_1 => sub { pred ('start') && $flags->{subsc_recv} == 1 };
   pred_action subsc_recv_1 => sub {
      $PRES->handle_subscription_request ($FJID2, $FJID1, 1, 1, "Ok, lets be!");
      print "ok 1 - sent subscription request\n";
   };

   pred_decl   subscribed_1 => sub { pred ('subsc_recv_1') && $flags->{subscribed} == 1 };
   pred_action subscribed_1 => sub {
      $PRES->send_unsubscription ($FJID1, $FJID2, 1, "Lets NOT be friends!");
      print "ok 2 - subscription successful, sending unsubscr.\n";
   };

   pred_decl
      unsubscribed_1 => sub { pred ('subscribed_1') && $flags->{unsubscribed} == 1 };
   pred_action unsubscribed_1 => sub {
      print "ok 3 - successfully unsubscribedd\n";
   };

};


AnyEvent::XMPP::Test::start (sub {
   my ($im, $cv, $pres) = @_;

   $IM   = $im;
   $PRES = $pres;
   $CV   = $cv;

   $im->reg_cb (
      recv_iq => sub {
         my ($im, $node) = @_;
         $im->stop_event if $node->find_all ([qw/roster query/]);
      }
   );

   $im->reg_cb (
      ext_presence_subscription_request => sub {
         my ($self, $resjid, $jid, $req) = @_;

         if (cmp_jid ($resjid, $FJID2) && $req->{status} =~ /friends/) {
            $flags->{subsc_recv}++;
            pred_check ($ctx);
         }
      },
      ext_presence_subscribed => sub {
         my ($self, $resjid, $jid) = @_;

         if (cmp_jid ($resjid, $FJID2)) {
            $flags->{subscribed}++;
            pred_check ($ctx);
         }
      },
      ext_presence_unsubscribed => sub {
         my ($self, $resjid, $jid) = @_;

         if (cmp_jid ($resjid, $FJID2) && pred ($ctx, 'subscribed_1')) {
            $flags->{unsubscribed}++;
            pred_check ($ctx);
         }
      },
      ext_presence_change => sub {
         my ($self, $resjid, $jid, $old, $new) = @_;

         if (cmp_jid ($resjid, $FJID2)
             && cmp_jid ($jid, $FJID1)
             && pred ($ctx, 'unsubscribed_1')) {

            print (($new->{show} eq 'unavailable' ? '' : 'not ')
                   . "ok 4 - new presence is unavailable\n");

            $cv->send;
         }
      }
   );

   pred_set ($ctx, 'start');

}, 'AnyEvent::XMPP::Ext::Presence');

undef $tout;

# print JSON->new->convert_blessed->pretty->encode ($pres_ext->{p}) . "\n";
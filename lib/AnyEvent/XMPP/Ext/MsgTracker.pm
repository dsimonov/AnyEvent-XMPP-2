package AnyEvent::XMPP::Ext::MsgTracker;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Util qw/stringprep_jid new_iq new_reply prep_bare_jid cmp_jid/;
use Scalar::Util qw/weaken/;
use strict;
no warnings;

use base qw/AnyEvent::XMPP::Ext/;

=head1 NAME

AnyEvent::XMPP::Ext::MsgTracker - Chat session message tracker

=head1 SYNOPSIS

   my $tracker = $con->add_ext ('MsgTracker');

   $tracker->reg_cb (
      destination_change => sub {
         my ($tracker, $resjid, $bare_jid, $full_jid) = @_;

         print "messages from $resjid to $bare_jid are now sent to $full_jid\n";
      }
   );

   $tracker->send (new_message (chat => "Hi there!", to => 'bare@jid'));

=head1 DESCRIPTION

This extension implements tracking of the destination of chat messages between
two persons in XMPP. The problem with private chats in XMPP is, that you should
reply to the I<full> JID that you received the last message from in private
chats.  This is necessary due to the fact the messages to the I<bare> JID are
only routed to the resource with the highest priority.

To use this you should use the C<send> method of the extension for private
communications.

The C<set> method can be used to preset or override tracking decisions of this
extension.

=head1 DEPENDENCIES

This extension requires the L<AnyEvent::XMPP::Ext::Presence>
extension.

=cut

sub required_extensions { 'AnyEvent::XMPP::Ext::Presence' }

=head1 METHODS

=over 4

=cut

sub disco_feature { }

sub init {
   my ($self) = @_;

   $self->{pres} = $self->{extendable}->get_ext ('Presence');

   $self->{pres}->reg_cb (
      change => sub {
         my ($pres, $resjid, $jid, $old, $new) = @_;

         my $bare = prep_bare_jid $jid;
         my $t = $self->{t}->{$resjid}
            or return;

         if (exists $t->{$bare}
             && $new->{show} eq 'unavailable'
             && cmp_jid ($t->{$bare}, $new->{jid})) {
            $self->destination_change ($resjid, $bare, undef);
         }
      }
   );

   $self->{iq_guard} = $self->{extendable}->reg_cb (
      recv_message => 400 => sub {
         my ($ext, $node) = @_;

         my $resjid = $node->meta->{dest};
         my $from = $node->attr ('from');
         my $bare = prep_bare_jid $from;

         my $t = ($self->{t}->{$resjid} ||= {});

         if (not (exists $t->{$bare})
             || !cmp_jid ($t->{$bare}, $from)) {
            $self->destination_change ($resjid, $bare, $from);
         }
      }
   );
}

=item $ext->set ($resjid, $fulljid)

This method can be used to tell the extension to track the full JID C<$fulljid>
for the client connection that connects the C<$resjid> resource.

=cut

sub set {
   my ($self, $resjid, $fulljid) = @_;

   $resjid = stringprep_jid $resjid;
   my $bare = prep_bare_jid $fulljid;

   $self->destination_change ($resjid, $bare, $fulljid);
}

=item $ext->send ($node)

This method will send the XMPP message in C<$node> that must be an
L<AnyEvent::XMPP::Node> instance. The C<to> field of the stanza will be updated
from the bare JID to the full JID when the bare JID is being tracked.

=cut

sub send {
   my ($self, $node) = @_;

   my $src = $node->meta->{src};
   my $to  = stringprep_jid $node->attr ('to');

   if (exists $self->{t}->{$src}
       && exists $self->{t}->{$src}->{$to}) {

      # only adjust to for bare JIDs in $to!

      $node->attr ('to', $self->{t}->{$src}->{$to});
   }

   $self->{extendable}->send ($node);
}

=back

=head1 EVENTS

=over 4

=item destination_change => $resjid, $bare_jid, $full_jid

Emitted whenever the destination full JID for C<$bare_jid> from C<$resjid>
changes. C<$full_jid> may either be the new destination or undefined in case
the resource went offline.

=cut

sub destination_change : event_cb {
   my ($self, $resjid, $bare_jid, $full_jid) = @_;

   if (defined $full_jid) {
      $self->{t}->{$resjid}->{$bare_jid} = $full_jid;

   } else {
      delete $self->{t}->{$resjid}->{$bare_jid};
   }
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009, 2010 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

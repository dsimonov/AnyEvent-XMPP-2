package Net::XMPP2::Ext::MUC::Room;
use strict;
use Net::XMPP2::Namespaces qw/xmpp_ns/;
use Net::XMPP2::Util qw/bare_jid prep_bare_jid cmp_jid split_jid join_jid is_bare_jid/;
use Net::XMPP2::Event;
use Net::XMPP2::Ext::MUC::User;
use Net::XMPP2::Error::MUC;

use constant {
   JOIN_SENT => 1,
   JOINED    => 2,
   LEFT      => 3,
};

our @ISA = qw/Net::XMPP2::Event/;

=head1 NAME

Net::XMPP2::Ext::MUC::Room - Room class

=head1 SYNOPSIS

=head1 DESCRIPTION

This module represents a room handle for a MUC.

=head1 METHODS

=over 4

=item B<new (%args)>

=cut

sub new {
   my $this = shift;
   my $class = ref($this) || $this;
   my $self = bless { status => LEFT, @_ }, $class;
   $self->init;
   $self
}

sub init {
   my ($self) = @_;
   $self->{jid} = bare_jid ($self->{jid});
}

sub handle_message {
   my ($self, $node) = @_;
   warn "HANDLE MESSAGE\n";
}

sub handle_presence {
   my ($self, $node) = @_;

   my $s = $self->{status};

   my $from    = $node->attr ('from');
   my $type    = $node->attr ('type');

   my $error;
   if ($node->attr ('type') eq 'error') {
      $error = Net::XMPP2::Error::Presence->new (node => $node);
   }

   if ($s == JOIN_SENT) {
      if ($error) {
         my $muce = Net::XMPP2::Error::MUC->new (
            presence_error => $error,
            type           => 'presence_error'
         );
         $self->event (join_error => $muce);
         $self->event (error      => $muce);

      } else {

         if (cmp_jid ($from, $self->nick_jid)) {
            my $user = $self->add_user_xml ($node);
            $self->{status} = JOINED;
            $self->event (enter => $user);

         } else {
            $self->add_user_xml ($node);
         }
      }
   } elsif ($s == JOINED) { # nick changes?

      if ($error) {
         my $muce = Net::XMPP2::Error::MUC->new (
            presence_error => $error,
            type           => 'presence_error'
         );
         $self->event (error      => $muce);

      } elsif ($type eq 'unavailable') {

         if (cmp_jid ($from, $self->nick_jid)) {
            $self->event ('leave');
            $self->we_left_room ();

         } else {
            my ($room, $srv, $nick) = split_jid ($from);

            my $user = delete $self->{users}->{$nick};
            if ($user) {
               $user->update ($node);
               $self->event (part => $user);
            } else {
               warn "User with '$nick' not found in room $self->{jid}!\n";
            }
         }
      } else {
         my $pre = $self->get_user ($from);
         my $user = $self->add_user_xml ($node);
         if ($pre) {
            $self->event (presence => $user);
         } else {
            $self->event (join     => $user);
         }
      }
   }
}

sub we_left_room {
   my ($self) = @_;
   $self->{users}  = {};
   $self->{status} = LEFT;
}

sub get_user {
   my ($self, $jid) = @_;
   my ($room, $srv, $nick) = split_jid ($jid);
   $self->{users}->{$nick}
}

sub add_user_xml {
   my ($self, $node) = @_;
   my $from = $node->attr ('from');
   my ($room, $srv, $nick) = split_jid ($from);

   my $user = $self->{users}->{$nick};
   unless ($user) {
      $user = $self->{users}->{$nick} =
         Net::XMPP2::Ext::MUC::User->new (room => $self, jid => $from);
   }

   $user->update ($node);

   $user
}

sub _join_jid_nick {
   my ($jid, $nick) = @_;
   my ($node, $host) = split_jid $jid;
   join_jid ($node, $host, $nick);
}

sub check_online {
   my ($self) = @_;
   unless ($self->is_connected) {
      warn "room $self not connected anymore!";
      return 0;
   }
   1
}

sub send_join {
   my ($self, $nick) = @_;
   $self->check_online or return;

   $self->{nick_jid} = _join_jid_nick ($self->{jid}, $nick);
   $self->{status}   = JOIN_SENT;

   my $con = $self->{muc}->{connection};
   $con->send_presence (undef, {
      defns => 'muc', node => { ns => 'muc', name => 'x' }
   }, to => $self->{nick_jid});
}

=item B<send_part ($msg)>

This lets you part the room, C<$msg> is an optional part message
and can be undef if no custom message should be generated.

=cut

sub send_part {
   my ($self, $msg) = @_;
   $self->check_online or return;
   my $con = $self->{muc}->{connection};
   $con->send_presence (
      'unavailable', undef,
      (defined $msg ? (status => $msg) : ()),
      to => $self->{nick_jid});
}

=item B<users>

Returns a list of L<Net::XMPP2::Ext::MUC::User> objects
which are in this room.

=cut

sub users {
   my ($self) = @_;
   values %{$self->{users}}
}

=item B<jid>

Returns the bare JID of this room.

=cut

sub jid      { $_[0]->{jid} }

=item B<nick_jid>

Returns the full JID of yourself in the room.

=cut

sub nick_jid { $_[0]->{nick_jid} }

=item B<is_connected>

Returns true if this room is still connected (but maybe not joined (yet)).

=cut

sub is_connected {
   my ($self) = @_;
   $self->{muc}
   && $self->{muc}->is_connected
}

=item B<is_joined>

Returns true if this room is still joined (and connected).

=cut

sub is_joined {
   my ($self) = @_;
   $self->is_connected
   && $self->{status} == JOINED
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2007 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
package AnyEvent::XMPP::Ext::VCard;
use AnyEvent::XMPP::Ext;
no warnings;
use strict;

use MIME::Base64;
use Digest::SHA1 qw/sha1_hex/;
use Scalar::Util;
use AnyEvent::XMPP::Namespaces qw/xmpp_ns/;
use AnyEvent::XMPP::Util qw/prep_bare_jid/;

use base qw/AnyEvent::XMPP::Ext/;

=head1 NAME

AnyEvent::XMPP::Ext::VCard - VCards (XEP-0054 & XEP-0153)

=head1 SYNOPSIS

   my $vcard = $con->add_ext ("VCard");

   $vcard->retrieve ($src, $jid, sub {
      my ($vcard, $src, $jid, $vcard, $error) = @_;

      if (defined $error) {
         print "error: " . $error->string . "\n";
      } else {
         # do something with $vcard
      }
   });

   $vcard->store ($src, $vcard, sub {
      my ($vcard, $src, $vcard, $error) = @_;
      # ...
   });

=head1 DESCRIPTION

This extension handles setting and retrieval of the VCard (XEP-0054) and the
VCard based avatars (XEP-0153).

For example see the test suite of L<AnyEvent::XMPP>.

=head1 METHODS

=over 4

=cut

sub required_extensions { 'AnyEvent::XMPP::Ext::Presence' }

sub disco_feature { xmpp_ns ('vcard') }

sub init {
   my ($self) = @_;

   # TODO: test
   $self->{pres}->reg_cb (
      generated_presence => sub {
         my ($pres, $node) = @_;

         my $photo_hash;

         if ($self->{vcards}->{$node->meta->{src}}) {
            $photo_hash = '';
            my $hash    = $self->{vcards}->{$node->meta->{src}}->{_avatar_hash};
            $photo_hash = $hash if defined $hash;
         }

         $node->add ({
            node => {
               dns  => 'vcard_upd',
               name => 'x',
               childs => [
                  defined $photo_hash
                     ? { name => 'photo',
                         childs => [
                             $photo_hash eq '' ? () : (\$photo_hash)
                         ]
                       }
                     : ()
               ]
            }
         });
      },
   );
}

sub hook_on {
   my ($self, $con, $dont_retrieve_vcard) = @_;

   Scalar::Util::weaken $self;

   my $rid =
      $con->reg_cb (
         ext_before_send_presence_hook => sub {
            my ($con) = @_;
            my $chlds;

            my $vc = $self->my_vcard ($con);

            if ($vc && !$vc->{_avatar}) {
               push @$chlds, { ns => xmpp_ns ('vcard_upd'), name => 'photo' }

            } elsif ($vc && $vc->{_avatar}) {
               push @$chlds, { 
                  ns => xmpp_ns ('vcard_upd'),
                  name => 'photo',
                  childs => [ $vc->{_avatar_hash} ]
               }
            }

            {
               defns => xmpp_ns ('vcard_upd'),
               node => {
                  ns => xmpp_ns ('vcard_upd'),
                  name => 'x',
                  ($chlds ? (childs => [ @$chlds ]) : ()),
              }
            }
         },
         ext_after_session_ready => sub {
            my ($con) = @_;

            if (not $dont_retrieve_vcard) {
               $self->retrieve ($con, undef, sub {
                  my ($jid, $vc, $error) = @_;

                  if ($error) {
                     $self->event (retrieve_vcard_error => $error);
                  }

                  # the own vcard was already set by retrieve
                  # this will push out an updated presence
                  $self->_publish_avatar;
               });
            }
         }
      );

   my $ar = [$con, $rid];
   Scalar::Util::weaken $ar->[0];
   push @{$self->{hooked}}, $ar;
}

sub _publish_avatar {
   my ($self) = @_;

   for (@{$self->{hooked}}) {
      if ($_->[0]) { $_->[0]->send_presence () }
   }
}

=item B<my_vcard ($con)>

This method returns the vcard for the account connected by C<$con>.
This only works if vcard was (successfully) retrieved. If the connection was
hoooked up the vcard was automatically retrieved.

Alternatively C<$con> can also be a string reprensenting the JID of an
account.

=cut

sub my_vcard {
   my ($self, $con) = @_;
   $self->{own_vcards}->{prep_bare_jid (ref ($con) ? $con->jid : $con)}
}

=item B<cache ([$newcache])>

See also C<new> about the meaning of cache hashes.
If no argument is given the current cache is returned.

=cut

sub cache {
   my ($self, $cache_hash) = @_;
   $self->{cache} = $cache_hash if defined $cache_hash;
   $self->{cache}
}

sub _store {
   my ($self, $con, $vcard_cb, $cb) = @_;

   $con->send_iq (
      set => sub {
         my ($w) = @_;
         $w->addPrefix (xmpp_ns ('vcard'), '');
         $w->startTag ([xmpp_ns ('vcard'), 'vCard']);
         $vcard_cb->($w);
         $w->endTag;

      }, sub {
         my ($xmlnode, $error) = @_;

         if ($error) {
            $cb->($error);
         } else {
            $cb->();
         }
      }
   );
}

=item B<store ($con, $vcard, $cb)>

This method will store your C<$vcard> on the connected server.
C<$cb> is called when either an error occured or the storage was successful.
If an error occured the first argument is not undefined and contains an
L<AnyEvent::XMPP::Error::IQ> object.

C<$con> should be a L<AnyEvent::XMPP::Connection> or an object from some derived class.

C<$vcard> has a datastructure as described below in B<VCARD STRUCTURE>.

=cut

sub store {
   my ($self, $con, $vcard, $cb) = @_;

   $self->_store ($con, sub {
      my ($w) = @_;
      $self->encode_vcard ($vcard, $w);
   }, sub {
      $cb->(@_);
   });
}

sub _retrieve {
   my ($self, $con, $dest, $cb) = @_;


   $con->send_iq (
      get => { defns => 'vcard', node => { ns => 'vcard', name => 'vCard' } },
      sub {
         my ($xmlnode, $error) = @_;

         if ($error) {
            $cb->(undef, undef, $error);

         } else {
            my ($vcard) = $xmlnode->find_all ([qw/vcard vCard/]);
            my $jid = $dest || prep_bare_jid ($con->jid);
            $vcard = $self->decode_vcard ($vcard);
            if (prep_bare_jid ($jid) eq prep_bare_jid ($con->jid)) {
               $self->{own_vcards}->{prep_bare_jid $con->jid} = $vcard;
            }
            $self->event (vcard => $jid, $vcard);
            $cb->($jid, $vcard, $error);
         }
      },
      (defined $dest ? (to => $dest) : ())
   );
}

=item B<retrieve ($con, $jid, $cb)>

This method will retrieve the vCard for C<$jid> via the connection C<$con>.
If C<$jid> is undefined the vCard of yourself is retrieved.
The callback C<$cb> is called when an error occured or the vcard was retrieved.
The first argument of the callback will be the JID to which the vCard belongs,
the second argument is the vCard itself (as described in B<VCARD STRUCTURE> below)
and the thrid argument is the error, if an error occured (undef otherwise).

=cut

sub retrieve {
   my ($self, $con, $dest, $cb) = @_;

   $self->_retrieve ($con, $dest, sub {
      my ($jid, $vc, $error) = @_;

      if ($error) { $cb->(undef, $error); return }
      else {
         $cb->($jid, $vc);
      }
   });
}

sub decode_vcard {
   my ($self, $vcard) = @_;
   my $ocard = {};

   for my $cn ($vcard->nodes) {
      if ($cn->nodes) {
         my $sub = {};
         for ($cn->nodes) {
            $sub->{$_->name} = $_->text
         }
         push @{$ocard->{$cn->name}}, $sub;
      } else {
         push @{$ocard->{$cn->name}}, $cn->text;
      }
   }

   if (my $p = $ocard->{PHOTO}) {
      my $first = $p->[0];

      if ($first->{BINVAL} ne '') {
         $ocard->{_avatar} = decode_base64 ($first->{BINVAL});
         $ocard->{_avatar_hash} = sha1_hex ($ocard->{_avatar});
         $ocard->{_avatar_type} = $first->{TYPE};
      }
   }

   $ocard
}

sub encode_vcard {
   my ($self, $vcardh, $w) = @_;

   if ($vcardh->{_avatar}) {
      $vcardh->{PHOTO} = [
         {
            BINVAL => encode_base64 ($vcardh->{_avatar}),
            TYPE => $vcardh->{_avatar_type}
         }
      ];
   }

   for my $ve (keys %$vcardh) {
      next if substr ($ve, 0, 1) eq '_';

      for my $el (@{ref ($vcardh->{$ve}) eq 'ARRAY' ? $vcardh->{$ve} : [$vcardh->{$ve}]}) {

         if (ref $el) {
            $w->startTag ([xmpp_ns ('vcard'), $ve]);

            for (keys %$el) {
               if ((not defined $el->{$_}) || $el->{$_} eq '') {
                  $w->emptyTag ([xmpp_ns ('vcard'), $_]);

               } else {
                  $w->startTag ([xmpp_ns ('vcard'), $_]);
                  $w->characters ($el->{$_});
                  $w->endTag;
               }
            }
            $w->endTag;

         } elsif ((not defined $el) || $el eq '') {
            $w->emptyTag ([xmpp_ns ('vcard'), $ve]);

         } else {
            $w->startTag ([xmpp_ns ('vcard'), $ve]);
            $w->characters ($el);
            $w->endTag;
         }
      }
   }
}

sub DESTROY {
   my ($self) = @_;
   $self->unreg_cb ($self->{cb_id});
   for (@{$self->{hooked}}) {
      $_->[0]->unreg_cb ($_->[1]) if defined $_->[0];
   }
}

=back

=head1 VCARD STRUCTURE

As there are currently no nice DOM implementations in Perl and I strongly
dislike the DOM API in general this module has a simple Perl datastructure
without cycles to represent the vCard.

First an example: A fetched vCard hash may look like this:

  {
    'URL' => ['http://www.ta-sa.org/'],
    'ORG' => [{
               'ORGNAME' => 'nethype GmbH'
             }],
    'N' => [{
             'FAMILY' => 'Redeker'
           }],
    'EMAIL' => ['elmex@ta-sa.org'],
    'BDAY' => ['1984-06-01'],
    'FN' => ['Robin'],
    'ADR' => [
       {
         HOME => undef,
         'COUNTRY' => 'Germany'
       },
       {
          WORK => undef,
          COUNTRY => 'Germany',
          LOCALITY => 'Karlsruhe'
       }
    ],
    'NICKNAME' => ['elmex'],
    'ROLE' => ['Programmer']
  }

The keys represent the toplevel element of a vCard, the values are always array
references containig one or more values for the key. If the value is a
hash reference again it's value will not be an array reference but either undef
or plain values.

The values of the toplevel keys are all array references because fields
like C<ADR> may occur multiple times.

Consult XEP-0054 for an explanation what these fields mean or contain.

There are special fields in this structure for handling avatars:
C<_avatar> contains the binary data for the avatar image.
C<_avatar_hash> contains the sha1 hexencoded hash of the binary image data.
C<_avatar_type> contains the mime type of the avatar.

If you want to store the vcard you only have to set C<_avatar> and C<_avatar_type>
if you want to store an avatar.

=head1 EVENTS

The vcard extension will emit these events:

=head1 TODO

Implement caching, the cache stuff is just a storage hash at the moment.
Or maybe drop it completly and let the application handle caching.

=over 4

=item retrieve_vcard_error => $iq_error

When a vCard retrieval was not successful, this event is emitted.
This is neccessary as some retrievals may happen automatically.

=item vcard => $jid, $vcard

Whenever a vCard is retrieved, either automatically or manually,
this event is emitted with the retrieved vCard.

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>, JID: C<< <elmex at jabber.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2007-2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

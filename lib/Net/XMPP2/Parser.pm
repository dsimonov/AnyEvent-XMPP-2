package Net::XMPP2::Parser;
use warnings;
use strict;
# OMFG!!!111 THANK YOU FOR THIS MODULE TO HANDLE THE XMPP INSANITY:
use Net::XMPP2::Node;
use XML::Parser::Expat;

=head1 NAME

Net::XMPP2::Parser - A parser for XML streams (helper for Net::XMPP2)

=head1 SYNOPSIS

   use Net::XMPP2::Parser;
   ...

=head1 DESCRIPTION

This is a XMPP XML parser helper class, which helps me to cope with the XMPP XML.

See also L<Net::XMPP2::Writer> for a discussion of the issues with XML in XMPP.

=head1 METHODS

=head2 new

This creates a new Net::XMPP2::Parser and calls C<init>.

=cut

sub new {
   my $this = shift;
   my $class = ref($this) || $this;
   my $self = { stanza_cb => sub { die "No stanza callback provided!" }, @_ };
   bless $self, $class;
   $self->init;
   $self
}

=head2 set_stanza_cb ($cb)

Sets the 'XML stanza' callback.

C<$cb> must be a code reference. The first argument to
the callback will be this Net::XMPP2::Parser instance and
the second will be the stanzas root Net::XMPP2::Node as first argument.

=cut

sub set_stanza_cb {
   my ($self, $cb) = @_;
   $self->{stanza_cb} = $cb;
}

=head2 init

This methods (re)initializes the parser.

=cut

sub init {
   my ($self) = @_;
   $self->{parser} = XML::Parser::ExpatNB->new (
      Namespaces => 1,
      ProtocolEncoding => 'UTF-8'
   );
   $self->{parser}->setHandlers (
      Start => sub { $self->cb_start_tag (@_) },
      End   => sub { $self->cb_end_tag   (@_) },
      Char  => sub { $self->cb_char_data (@_) },
   );
   $self->{nso} = {};
   $self->{nodestack} = [];
}

=head2 nseq ($namespace, $tagname, $cmptag)

This method checks whether the C<$cmptag> matches the C<$tagname>
in the C<$namespace>.

C<$cmptag> needs to come from the XML::Parser::Expat as it has
some magic attached that stores the namespace.

=cut

sub nseq {
   my ($self, $ns, $name, $tag) = @_;

   unless (exists $self->{nso}->{$ns}->{$name}) {
      $self->{nso}->{$ns}->{$name} =
         $self->{parser}->generate_ns_name ($name, $ns);
   }

   return $self->{parser}->eq_name ($self->{nso}->{$ns}->{$name}, $tag);
}

=head2 feed ($data)

This method feeds a chunk of unparsed data to the parser.

=cut

sub feed {
   my ($self, $data) = @_;
   $self->{parser}->parse_more ($data);
}


sub cb_start_tag {
   my ($self, $p, $el, %attrs) = @_;
   push @{$self->{nodestack}}, Net::XMPP2::Node->new ($p->namespace ($el), $el, \%attrs, $self);
}

sub cb_char_data {
   my ($self, $p, $str) = @_;
   unless (@{$self->{nodestack}}) {
      warn "characters outside of tag: [$str]!\n";
      return;
   }
   $self->{nodestack}->[-1]->add_text ($str);
}

sub cb_end_tag {
   my ($self, $p, $el) = @_;

   unless (@{$self->{nodestack}}) {
      warn "end tag </$el> read without any starting tag!\n";
      return;
   }

   if (!$p->eq_name ($self->{nodestack}->[-1]->name, $el)) {
      warn "end tag </$el> doesn't match start tags ($self->{tags}->[-1]->[0])!\n";
      return;
   }

   my $node = pop @{$self->{nodestack}};

   # > 1 because we don't want the stream tag to save all our children...
   if (@{$self->{nodestack}} > 1) {
      $self->{nodestack}->[-1]->add_node ($node);
   }

   if (@{$self->{nodestack}} == 1) {
      $self->{stanza_cb}->($self, $node);
   }
}

=head1 AUTHOR

Robin Redeker, C<< <elmex at ta-sa.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2007 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Net::XMPP2
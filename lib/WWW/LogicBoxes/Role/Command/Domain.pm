package WWW::LogicBoxes::Role::Command::Domain;

use strict;
use warnings;

use Moose::Role;
use MooseX::Params::Validate;

use WWW::LogicBoxes::Types qw( Bool DomainName DomainNames Int PrivateNameServer Str );

use WWW::LogicBoxes::Domain::Factory;

use Try::Tiny;
use Carp;

use Readonly;
Readonly my $DOMAIN_DETAIL_OPTIONS => [qw( All )];

requires 'submit';

# VERSION
# ABSTRACT: Domain API Calls

sub get_domain_by_id {
    my $self = shift;
    my ( $domain_id ) = pos_validated_list( \@_, { isa => Int } );

    return try {
        my $response = $self->submit({
            method => 'domains__details',
            params => {
                'order-id' => $domain_id,
                'options'  => $DOMAIN_DETAIL_OPTIONS,
            }
        });

        return WWW::LogicBoxes::Domain::Factory->construct_from_response( $response );
    }
    catch {
        if( $_ =~ m/^No Entity found for Entityid/ ) {
            return;
        }

        croak $_;
    };
}

sub get_domain_by_name {
    my $self = shift;
    my ( $domain_name ) = pos_validated_list( \@_, { isa => DomainName } );

    return try {
        my $response = $self->submit({
            method => 'domains__details_by_name',
            params => {
                'domain-name' => $domain_name,
                'options'     => $DOMAIN_DETAIL_OPTIONS,
            }
        });

        return WWW::LogicBoxes::Domain::Factory->construct_from_response( $response );
    }
    catch {
        if( $_ =~ m/^Website doesn't exist for/ ) {
            return;
        }

        croak $_;
    };
}

sub update_domain_contacts {
    my $self = shift;
    my ( %args ) = validated_hash(
        \@_,
        id                    => { isa => Int },
        registrant_contact_id => { isa => Int, optional => 1 },
        admin_contact_id      => { isa => Int, optional => 1 },
        technical_contact_id  => { isa => Int, optional => 1 },
        billing_contact_id    => { isa => Int, optional => 1 },
    );

    return try {
        my $original_domain = $self->get_domain_by_id( $args{id} );

        if( !$original_domain ) {
            croak 'No such domain exists';
        }

        my $contact_mapping = {
            registrant_contact_id => 'reg-contact-id',
            admin_contact_id      => 'admin-contact-id',
            technical_contact_id  => 'tech-contact-id',
            billing_contact_id    => 'billing-contact-id',
        };

        my $num_changes = 0;
        my $contacts_to_update;
        for my $contact_type ( keys %{ $contact_mapping } ) {
            if( $args{$contact_type} && $args{$contact_type} != $original_domain->$contact_type ) {
                $contacts_to_update->{ $contact_mapping->{ $contact_type } } = $args{ $contact_type };
                $num_changes++;
            }
            else {
                $contacts_to_update->{ $contact_mapping->{ $contact_type } } = $original_domain->$contact_type;
            }
        }

        if( $num_changes == 0 ) {
            return $original_domain;
        }

        $self->submit({
            method => 'domains__modify_contact',
            params => {
                'order-id'    => $args{id},
                %{ $contacts_to_update }
            }
        });

        return $self->get_domain_by_id( $args{id} );
    }
    catch {
        ## no critic (ControlStructures::ProhibitCascadingIfElse)
        if( $_ =~ m/{registrantcontactid=registrantcontactid is invalid}/ ) {
            croak 'Invalid registrant_contact_id specified';
        }
        elsif( $_ =~ m/{admincontactid=admincontactid is invalid}/ ) {
            croak 'Invalid admin_contact_id specified';
        }
        elsif( $_ =~ m/{techcontactid=techcontactid is invalid}/ ) {
            croak 'Invalid technical_contact_id specified';
        }
        elsif( $_ =~ m/{billingcontactid=billingcontactid is invalid}/ ) {
            croak 'Invalid billing_contact_id specified';
        }
        ## use critic

        croak $_;
    };
}

sub enable_domain_lock_by_id {
    my $self = shift;
    my ( $domain_id ) = pos_validated_list( \@_, { isa => Int } );

    return try {
        $self->submit({
            method => 'domains__enable_theft_protection',
            params => {
                'order-id' => $domain_id,
            }
        });

        return $self->get_domain_by_id( $domain_id );
    }
    catch {
        if( $_ =~ m/^No Entity found for Entityid/ ) {
            croak 'No such domain';
        }

        croak $_;
    };
}

sub disable_domain_lock_by_id {
    my $self = shift;
    my ( $domain_id ) = pos_validated_list( \@_, { isa => Int } );

    return try {
        $self->submit({
            method => 'domains__disable_theft_protection',
            params => {
                'order-id' => $domain_id,
            }
        });

        return $self->get_domain_by_id( $domain_id );
    }
    catch {
        if( $_ =~ m/^No Entity found for Entityid/ ) {
            croak 'No such domain';
        }

        croak $_;
    };
}

sub enable_domain_privacy {
    my $self = shift;
    my ( %args ) = validated_hash(
        \@_,
        id     => { isa => Int },
        reason => { isa => Str, optional => 1 },
    );

    $args{reason} //= 'Enabling Domain Privacy';

    return $self->_set_domain_privacy(
        id     => $args{id},
        status => 1,
        reason => $args{reason},
    );
}

sub disable_domain_privacy {
    my $self = shift;
    my ( %args ) = validated_hash(
        \@_,
        id     => { isa => Int },
        reason => { isa => Str, optional => 1 },
    );

    $args{reason} //= 'Disabling Domain Privacy';

    return try {
        return $self->_set_domain_privacy(
            id     => $args{id},
            status => 0,
            reason => $args{reason},
        );
    }
    catch {
        if( $_ =~ m/^Privacy Protection not Purchased/ ) {
            return $self->get_domain_by_id( $args{id} );
        }

        croak $_;
    };
}

sub _set_domain_privacy {
    my $self = shift;
    my ( %args ) = validated_hash(
        \@_,
        id     => { isa => Int },
        status => { isa => Bool },
        reason => { isa => Str },
    );

    return try {
        $self->submit({
            method => 'domains__modify_privacy_protection',
            params => {
                'order-id'        => $args{id},
                'protect-privacy' => $args{status} ? 'true' : 'false',
                'reason'          => $args{reason},
            }
        });

        return $self->get_domain_by_id( $args{id} );
    }
    catch {
        if( $_ =~ m/^No Entity found for Entityid/ ) {
            croak 'No such domain';
        }

        croak $_;
    };
}

sub update_domain_nameservers {
    my $self = shift;
    my ( %args ) = validated_hash(
        \@_,
        id          => { isa => Int },
        nameservers => { isa => DomainNames },
    );

    return try {
        $self->submit({
            method => 'domains__modify_ns',
            params => {
                'order-id' => $args{id},
                'ns'       => $args{nameservers},
            }
        });

        return $self->get_domain_by_id( $args{id} );
    }
    catch {
        if( $_ =~ m/^No Entity found for Entityid/ ) {
            croak 'No such domain';
        }
        elsif( $_ =~ m/is not a valid Nameserver/ ) {
            croak 'Invalid nameservers provided';
        }
        elsif( $_ =~ m/Same value for new and old NameServers/ ) {
            return $self->get_domain_by_id( $args{id} );
        }

        croak $_;
    };
}

1;

__END__
=pod

=head1 NAME

WWW::LogicBoxes::Role::Command::Domain - Domain Related Operations

=head1 SYNOPSIS

    use WWW::LogicBoxes;
    use WWW::LogicBoxes::Contact;
    use WWW::LogicBoxes::Domain;

    my $logic_boxes = WWW::LogicBoxes->new( ... );

    # Retrieval
    my $domain = $logic_boxes->get_domain_by_id( 42 );
    my $domain = $logic_boxes->get_domain_by_domain( 'test-domain.com' );

    # Update Contacts
    my $contacts = {
        registrant_contact => WWW::LogicBoxes::Contact->new( ... ),
        admin_contact      => WWW::LogicBoxes::Contact->new( ... ),
        technical_contact  => WWW::LogicBoxes::Contact->new( ... ),
        billing_contact    => WWW::LogicBoxes::Contact->new( ... ),
    };

    $logic_boxes->update_domain_contacts(
        id                    => $domain->id,
        registrant_contact_id => $contacts->{registrant_contact}->id,
        admin_contact_id      => $contacts->{admin_contact}->id,
        technical_contact_id  => $contacts->{technical_contact}->id,
        billing_contact_id    => $contacts->{billing_contact}->id,
    );

    # Domain Locking
    $logic_boxes->enable_domain_lock_by_id( $domain->id );
    $logic_boxes->disable_domain_lock_by_id( $domain->id );

    # Domain Privacy
    $logic_boxes->enable_domain_privacy(
        id     => $domain->id,
        reason => 'Enabling Domain Privacy',
    );

    $logic_boxes->disable_domain_privacy(
        id     => $domain->id,
        reason => 'Disabling Domain Privacy',
    );

    # Nameservers
    $logic_boxes->update_domain_nameservers(
        id          => $domain->id,
        nameservers => [ 'ns1.logicboxes.com', 'ns1.logicboxes.com' ],
    );

=head1 REQUIRES

submit

=head1 DESCRIPTION

Implements domain related operations with the L<LogicBoxes's|http://www.logicboxes.com> API.

=head2 See Also

=over 4

=item For Domain Registration please see L<WWW::LogicBoxes::Role::Command::Domain::Registration>

=item For Domain Availability please see L<WWW::LogicBoxes::Role::Command::Domain::Availability>

=item For Private Nameservers please see L<WWW::LogicBoxes::Role::Command::Domain::PrivateNameServer>

=back

=head1 METHODS

=head2 get_domain_by_id

    use WWW::LogicBoxes;
    use WWW::LogicBoxes::Domain;

    my $logic_boxes = WWW::LogicBoxes->new( ... );
    my $domain      = $logic_boxes->get_domain_by_id( 42 );

Given a Integer L<domain|WWW::LogicBoxes::Domain> id, returns a matching L<WWW::LogicBoxes::Domain> from L<LogicBoxes|http://www.logicobxes.com>.  In the event of no matching L<domain|WWW::LogicBoxes::Domain>, returns undef.

B<NOTE> For domain transfers that are in progress a L<domain_transfer|WWW::LogicBoxes::DomainTransfer> record will be returned.

=head2 get_domain_by_name

    use WWW::LogicBoxes;
    use WWW::LogicBoxes::Domain;

    my $logic_boxes = WWW::LogicBoxes->new( ... );
    my $domain      = $logic_boxes->get_domain_by_domain( 'test-domain.com' );

Given a full L<domain|WWW::LogicBoxes::Domain> name, returns a matching L<WWW::LogicBoxes::Domain> from L<LogicBoxes|http://www.logicobxes.com>.  In the event of no matching L<domain|WWW::LogicBoxes::Domain>, returns undef,

B<NOTE> For domain transfers that are in progress a L<domain_transfer|WWW::LogicBoxes::DomainTransfer> record will be returned.

=head2 update_domain_contacts

    use WWW::LogicBoxes;
    use WWW::LogicBoxes::Contact;
    use WWW::LogicBoxes::Domain;

    my $logic_boxes = WWW::LogicBoxes->new( ... );

    # Update Contacts
    my $contacts = {
        registrant_contact => WWW::LogicBoxes::Contact->new( ... ),
        admin_contact      => WWW::LogicBoxes::Contact->new( ... ),
        technical_contact  => WWW::LogicBoxes::Contact->new( ... ),
        billing_contact    => WWW::LogicBoxes::Contact->new( ... ),
    };

    $logic_boxes->update_domain_contacts(
        id                    => $domain->id,
        registrant_contact_id => $contacts->{registrant_contact}->id,
        admin_contact_id      => $contacts->{admin_contact}->id,
        technical_contact_id  => $contacts->{technical_contact}->id,
        billing_contact_id    => $contacts->{billing_contact}->id,
    );

Given a L<domain|WWW::LogicBoxes::Domain> id and optionally a L<contact|WWW::LogicBoxes::Contact> id for registrant_contact_id, admin_contact_id, technical_contact_id, and/or billing_contact_id, updates the L<domain|WWW::LogicBoxes::Domain> contacts.  This method is smart enough to not request a change if the contact hasn't been updated and consumers need only specify the elements that are changing.

=head2 enable_domain_lock_by_id

    use WWW::LogicBoxes;
    use WWW::LogicBoxes::Domain;

    my $logic_boxes = WWW::LogicBoxes->new( ... );
    $logic_boxes->enable_domain_lock_by_id( $domain->id );

Given an Integer L<domain|WWW::LogicBoxes::Domain> id, locks the L<domain|WWW::LogicBoxes::Domain> so that it can not be transfered away.

=head2 disable_domain_lock_by_id

    use WWW::LogicBoxes;
    use WWW::LogicBoxes::Domain;

    my $logic_boxes = WWW::LogicBoxes->new( ... );
    $logic_boxes->disable_domain_lock_by_id( $domain->id );

Given an Integer L<domain|WWW::LogicBoxes::Domain> id, unlocks the L<domain|WWW::LogicBoxes::Domain> so that it can be transfered away.

=head2 enable_domain_privacy

    use WWW::LogicBoxes;
    use WWW::LogicBoxes::Domain;

    my $logic_boxes = WWW::LogicBoxes->new( ... );
    $logic_boxes->enable_domain_privacy(
        id     => $domain->id,
        reason => 'Enabling Domain Privacy',
    );

Given an Integer L<domain|WWW::LogicBoxes::Domain> id and an optional reason ( defaults to "Enabling Domain Privacy" ), enables WHOIS Privacy Protect for the L<domain|WWW::LogicBoxes::Domain>.

=head2 disable_domain_privacy

    use WWW::LogicBoxes;
    use WWW::LogicBoxes::Domain;

    my $logic_boxes = WWW::LogicBoxes->new( ... );
    $logic_boxes->disable_domain_privacy(
        id     => $domain->id,
        reason => 'Disabling Domain Privacy',
    );

Given an Integer L<domain|WWW::LogicBoxes::Domain> id and an optional reason ( defaults to "Disabling Domain Privacy" ), disabled WHOIS Privacy Protect for the L<domain|WWW::LogicBoxes::Domain>.

=head2 update_domain_nameservers

    use WWW::LogicBoxes;
    use WWW::LogicBoxes::Domain;

    my $logic_boxes = WWW::LogicBoxes->new( ... );
    $logic_boxes->update_domain_nameservers(
        id          => $domain->id,
        nameservers => [ 'ns1.logicboxes.com', 'ns1.logicboxes.com' ],
    );

Given an Integer L<domain|WWW::LogicBoxes::Domain> id and an ArrayRef of nameserver hostnames, sets the L<domain|WWW::LogicBoxes::Domain>'s authoritative nameservers.

=cut

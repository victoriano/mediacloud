package MediaWords::Controller::Api::V2::Tags;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;

use MediaWords::Controller::Api::V2::MC_REST_SimpleObject;

use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

__PACKAGE__->config(
    action => {
        single => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        list   => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        update => { Does => [ qw( ~AdminAuthenticated ~Throttled ~Logged ) ] },
        create => { Does => [ qw( ~AdminAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub get_name_search_clause
{
    my ( $self, $c ) = @_;

    my $v = $c->req->params->{ search };

    return '' unless ( $v );

    return 'and false' unless ( length( $v ) > 2 );

    my $qv = $c->dbis->quote( $v );

    return <<END;
and tags_id in (
    select t.tags_id
        from tags t
            join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
        where
            t.tag ilike '%' || $qv || '%' or
            t.label ilike '%' || $qv || '%' or
            ts.name ilike '%' || $qv || '%' or
            ts.label ilike '%' || $qv || '%'
)
END
}

sub get_table_name
{
    return "tags";
}

sub list_optional_query_filter_field
{
    return 'tag_sets_id';
}

sub get_extra_where_clause
{
    my ( $self, $c ) = @_;

    if ( my $similar_tags_id = $c->req->params->{ similar_tags_id } )
    {
        # make sure this is an int
        $similar_tags_id += 0;

        my $clause = <<SQL;
and tags_id in (
    select b.tags_id
        from media_tags_map a
            join media_tags_map b using ( media_id )
        where
            a.tags_id = $similar_tags_id and
            a.tags_id <> b.tags_id
        group by b.tags_id
        order by count(*) desc
        limit 100
)
SQL

        return $clause;
    }

    return '';
}

sub single_GET
{
    my ( $self, $c, $id ) = @_;

    my $items = $c->dbis->query( <<END, $id )->hashes();
select t.tags_id, t.tag_sets_id, t.label, t.description, t.tag,
        ts.name tag_set_name, ts.label tag_set_label, ts.description tag_set_description,
        t.show_on_media OR ts.show_on_media show_on_media,
        t.show_on_stories OR ts.show_on_stories show_on_stories,
        t.is_static
    from tags t
        join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
    where
        t.tags_id = ?
END

    $self->status_ok( $c, entity => $items );
}

sub _fetch_list($$$$$$)
{
    my ( $self, $c, $last_id, $table_name, $id_field, $rows ) = @_;

    my $public = $c->req->params->{ public } || '';

    my $public_clause =
      $public eq '1' ? 't.show_on_media or ts.show_on_media or t.show_on_stories or ts.show_on_stories' : '1=1';

    $c->dbis->query( <<END );
create temporary view tags as
    select t.tags_id, t.tag_sets_id, t.label, t.description, t.tag,
        ts.name tag_set_name, ts.label tag_set_label, ts.description tag_set_description,
        t.show_on_media OR ts.show_on_media show_on_media,
        t.show_on_stories OR ts.show_on_stories show_on_stories,
        t.is_static
    from tags t
        join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
    where $public_clause
END

    return $self->SUPER::_fetch_list( $c, $last_id, $table_name, $id_field, $rows );
}

sub get_update_fields($)
{
    return [ qw/tag label description show_on_media show_on_stories is_static/ ];
}

sub update : Local : ActionClass('MC_REST')
{
}

sub update_PUT
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    $self->require_fields( $c, [ qw/tags_id/ ] );

    my $tag = $c->dbis->require_by_id( 'tags', $data->{ tags_id } );
    my $tag_set = $c->dbis->require_by_id( 'tag_sets', $data->{ tag_sets_id } ) if ( $data->{ tag_sets_id } );

    my $input = { map { $_ => $data->{ $_ } } grep { exists( $data->{ $_ } ) } @{ $self->get_update_fields } };

    my $updated_tag = $c->dbis->update_by_id( 'tags', $data->{ tags_id }, $input );

    return $self->status_ok( $c, entity => { tag => $updated_tag } );
}

sub create : Local : ActionClass( 'MC_REST' )
{
}

sub create_GET
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    $self->require_fields( $c, [ qw/tag_sets_id tag label/ ] );

    my $fields = [ 'tag_sets_id', @{ $self->get_update_fields } ];
    my $input = { map { $_ => $data->{ $_ } } grep { exists( $data->{ $_ } ) } @{ $fields } };

    my $created_tag = $c->dbis->create( 'tags', $input );

    return $self->status_ok( $c, entity => { tag => $created_tag } );
}

1;

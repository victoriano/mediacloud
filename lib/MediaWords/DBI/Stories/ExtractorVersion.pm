package MediaWords::DBI::Stories::ExtractorVersion;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::ExtractText;
use MediaWords::Util::Tags;

# cached ids of tags, which should change rarely
my $_tags_id_cache = {};

# get cached id of the tag.  create the tag if necessary.
# we need this to make tag lookup very fast for add_default_tags
sub _get_tags_id($$$)
{
    my ( $db, $tag_sets_id, $term ) = @_;

    if ( $_tags_id_cache->{ $tag_sets_id }->{ $term } )
    {
        return $_tags_id_cache->{ $tag_sets_id }->{ $term };
    }

    my $tag = $db->find_or_create(
        'tags',
        {
            tag         => $term,
            tag_sets_id => $tag_sets_id
        }
    );

    #Commit to make sure cache and database are consistent
    $db->autocommit() || $db->commit;

    $_tags_id_cache->{ $tag_sets_id }->{ $term } = $tag->{ tags_id };

    return $tag->{ tags_id };
}

my $_extractor_version_tag_set;

sub _get_extractor_version_tag_set($)
{
    my $db = shift;

    if ( !defined( $_extractor_version_tag_set ) )
    {
        $_extractor_version_tag_set = MediaWords::Util::Tags::lookup_or_create_tag_set( $db, "extractor_version" );
    }

    return $_extractor_version_tag_set;
}

sub _get_current_extractor_version_tags_id($)
{
    my $db = shift;

    my $extractor_version = MediaWords::Util::ExtractText::extractor_name();
    my $tag_set           = _get_extractor_version_tag_set( $db );

    my $tags_id = _get_tags_id( $db, $tag_set->{ tag_sets_id }, $extractor_version );

    return $tags_id;
}

# add extractor version tag
sub update_extractor_version_tag($$$)
{
    my ( $db, $story, $extractor_args ) = @_;

    my $tag_set = _get_extractor_version_tag_set( $db );

    $db->query( <<END, $tag_set->{ tag_sets_id }, $story->{ stories_id } );
delete from stories_tags_map stm
    using tags t
        join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id )
    where
        t.tags_id = stm.tags_id and
        ts.tag_sets_id = ? and
        stm.stories_id = ?
END

    my $tags_id = _get_current_extractor_version_tags_id( $db );

    $db->query( <<END, $story->{ stories_id }, $tags_id );
insert into stories_tags_map ( stories_id, tags_id, db_row_last_updated ) values ( ?, ?, now() )
END

}

1;

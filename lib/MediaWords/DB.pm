package MediaWords::DB;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;

use List::Util qw( first );

use MediaWords::DB::Handler;

use MediaWords::Util::Config;

use MediaWords::Test::DB;

# returns connection info from the configuration file
# if no connection label is supplied and no connections have been made,
# the first connection in the config is used otherwise the last used settings
# are returned
sub connect_info
{
    my ( $label ) = @_;

    my $settings = connect_settings( $label );

    unless ( defined $settings )
    {
        LOGCONFESS "Settings is undefined";
    }
    unless ( $settings->{ db } and $settings->{ host } )
    {
        LOGCONFESS "Settings is uncomplete ('db' and 'host' must both be set)";
    }

    my $data_source = 'dbi:Pg:dbname=' . $settings->{ db } . ';host=' . $settings->{ host };

    if ( defined( $settings->{ port } ) )
    {
        $data_source .= ';port=' . $settings->{ port };
    }

    # Arguments for MediaWords::DB::Handler->connect()
    return (
        $settings->{ host },    #
        $settings->{ port },    #
        $settings->{ user },    #
        $settings->{ pass },    #
        $settings->{ db }       #
    );
}

sub connect_to_db(;$$)
{
    my ( $label, $do_not_check_schema_version ) = @_;

    my $ret = MediaWords::DB::Handler->connect( connect_info( $label ), $do_not_check_schema_version );

    die "Error in connect_to_db $@" unless defined( $ret );

    my $config = MediaWords::Util::Config::get_config();

    if ( defined( $config->{ mediawords }->{ db_statement_timeout } ) )
    {
        $ret->query( " SET statement_timeout TO ? ", $config->{ mediawords }->{ db_statement_timeout } );
    }

    # Reset the session variable in case the database connection is being reused due to pooling.

    my $query = <<'END_SQL';
DO $$
BEGIN
PERFORM enable_story_triggers();
EXCEPTION
WHEN undefined_function THEN
    -- This exception will be raised if the database is uninitialized at this point.
    -- So, don't emit any kind of error because of an non-existent function.
    NULL;
WHEN OTHERS THEN
    -- Forward the exception
    RAISE;
END
$$;

END_SQL

    $ret->query( $query );
    $ret->autocommit() || $ret->commit;

    return $ret;
}

sub connect_settings
{
    my ( $label ) = @_;

    # If this is Catalyst::Test run, force the label to the test database
    if ( MediaWords::Test::DB::using_test_database() )
    {
        $label = 'test';
    }

    my $all_settings = MediaWords::Util::Config::get_config->{ database };

    defined( $all_settings ) or LOGCROAK( "No database connections configured" );

    my $connect_settings;
    if ( defined( $label ) )
    {
        $connect_settings = first { $_->{ label } eq $label } @{ $all_settings }
          or LOGCROAK "No database connection settings labeled '$label'";
    }

    unless ( defined( $connect_settings ) )
    {
        $connect_settings = $all_settings->[ 0 ];
    }

    return $connect_settings;
}

sub get_db_labels
{
    my $all_settings = MediaWords::Util::Config::get_config->{ database };

    defined( $all_settings ) or LOGCROAK( "No database connections configured" );

    my @labels = map { $_->{ label } } @{ $all_settings };

    return @labels;
}

sub _set_environment_vars_for_db
{
    my ( $label ) = @_;

    my $connect_settings = connect_settings( $label );

    $ENV{ 'PGPASSWORD' } = $connect_settings->{ pass };
    $ENV{ 'PGPORT' }     = $connect_settings->{ port };
    $ENV{ 'PGHOST' }     = $connect_settings->{ host };
    $ENV{ 'PGDATABASE' } = $connect_settings->{ db };
    $ENV{ 'PGUSER' }     = $connect_settings->{ user };
}

sub exec_psql_for_db
{
    my ( $label, @ARGS ) = @_;

    _set_environment_vars_for_db( $label );

    exec( 'psql', @ARGS );
    die 'exec failed';
}

sub print_shell_env_commands_for_psql
{
    my ( $label, @ARGS ) = @_;

    _set_environment_vars_for_db( $label );

    my $psql_env_vars = [ qw ( PGPASSWORD PGHOST PGDATABASE PGUSER PGPORT) ];

    foreach my $psql_env_var ( @{ $psql_env_vars } )
    {
        if ( $ENV{ $psql_env_var } )
        {
            say "export $psql_env_var=" . $ENV{ $psql_env_var };
        }
    }
}

my $_disable_story_triggers = 0;

sub story_triggers_disabled
{
    return $_disable_story_triggers;
}

sub disable_story_triggers
{
    $_disable_story_triggers = 1;
    return;
}

sub enable_story_triggers
{
    $_disable_story_triggers = 0;
    return;
}

# match the database name against the database names in mediawords.yml to find the current label
sub get_label
{
    my ( $db ) = @_;

    my $database_name = $db->query( "select current_database()" )->flat;

    my $config = MediaWords::Util::Config::get_config;

    for my $database_info ( @{ $config->{ database } } )
    {
        return $database_info->{ label } if ( $database_info->{ db } eq $database_name );
    }

    return undef;
}

# You can replace this text with custom content, and it will be preserved on regeneration
1;

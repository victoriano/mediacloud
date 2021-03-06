package MediaWords;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;

use Catalyst::Runtime '5.80';
use v5.22;

#use Catalyst::Runtime;

use MediaWords::DB::Handler;
use MediaWords::Util::Config;
use MediaWords::DBI::Auth::Roles;

use URI;

# Set flags and add plugins for the application
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a YAML file in the
#                 application's home directory
# Plugin::Static::Simple: will serve static files from the application's root
#                 directory

use Catalyst qw/
  ConfigLoader
  ConfigDefaults
  Static::Simple
  StackTrace
  I18N
  Authentication
  Authorization::Roles
  Authorization::ACL
  Session
  Session::Store::File
  Session::State::Cookie
  /;

our $VERSION = '0.01';

use HTML::FormFu;
use HTML::FormFu::Unicode;

# Configure the application.
#
# Note that settings in mediawords.yml (or other external
# configuration file that you set up manually) take precedence
# over this when using ConfigLoader. Thus configuration
# details given here can function as a default configuration,
# with a external configuration file acting as an override for
# local deployment.

my $config = __PACKAGE__->config( -name => 'MediaWords' );

# Configure authentication scheme
__PACKAGE__->config( 'Plugin::Static::Simple' => { dirs => [ 'gexf', 'nv' ] } );
__PACKAGE__->config(
    'Plugin::Authentication' => {
        'default_realm' => 'users',
        'users'         => {
            'credential' => {
                'class'              => 'Password',
                'password_field'     => 'password',
                'password_type'      => 'salted_hash',
                'password_hash_type' => 'SHA-256',
                'password_salt_len'  => 64,
            },
            'store' => { 'class' => 'MediaWords' }
        }
    }
);

# Exit an action chain when there is an error raised in any action (thus
# terminating the chain early)
__PACKAGE__->config( abort_chain_on_error_fix => 1 );

# Start the application
__PACKAGE__->setup;

# Access rules; created on the "disallow everything but explicitly allow this" basis
# (https://metacpan.org/module/Catalyst::Plugin::Authorization::ACL)
sub setup_acl()
{

    # Admin read-only interface
    my @acl_admin_readonly = qw|
      /admin/downloads/list
      /admin/downloads/view
      /admin/downloads/view_extracted
      /admin/feeds/list
      /admin/media/do_eval_rss_full_text
      /admin/media/do_find_likely_full_text_rss
      /admin/media/eval_rss_full_text
      /admin/media/find_likely_full_text_rss
      /admin/media/list
      /admin/media/media_tags_search_json
      /admin/media/search
      /admin/stories/list
      /admin/stories/stories_query_json
      /admin/stories/tag
      /admin/stories/view
      /admin/users/list
      |;

    # media-edit role; can do everything admin-readonly can + add / edit media / feeds
    my @acl_media_edit = qw|
      /admin/downloads/redownload
      /admin/feeds/batch_create
      /admin/feeds/batch_create_do
      /admin/feeds/create
      /admin/feeds/create_do
      /admin/feeds/delete
      /admin/feeds/edit
      /admin/feeds/edit_do
      /admin/feeds/edit_tags
      /admin/feeds/edit_tags_do
      /admin/feeds/scrape
      /admin/feeds/scrape_import
      /admin/media/create_batch
      /admin/media/create_do
      /admin/media/delete
      /admin/media/edit
      /admin/media/edit_do
      /admin/media/edit_tags
      /admin/media/edit_tags_do
      /admin/media/moderate
      /admin/media/moderate/merge
      /admin/health
      /admin/health/list
      /admin/health/tag
      /admin/health/medium
      /admin/health/stories
      /admin/tags/edit
      /admin/tagsets/edit
      |;

    # stories-edit role; can do everything admin-readonly can + add / edit stories
    my @acl_stories_edit = qw|
      /admin/stories/add_tag
      /admin/stories/add_tag_do
      /admin/stories/delete_tag
      /admin/stories/edit
      /admin/tags/edit
      /admin/tagsets/edit
      |;

    # cm role; can access all cm pages + admin-readonly + media-edit + stories-edi
    my @acl_cm = qw|
      /admin/tm/
      |;

    my @acl_search = qw|
      /search
      /search/index
      /search/wc
      /search/readme
      /search/diff
      |;

    foreach my $path ( @acl_admin_readonly )
    {
        __PACKAGE__->allow_access_if_any(
            $path,
            [
                $MediaWords::DBI::Auth::Roles::ADMIN_READONLY,    #
                $MediaWords::DBI::Auth::Roles::MEDIA_EDIT,        #
                $MediaWords::DBI::Auth::Roles::STORIES_EDIT,      #
                $MediaWords::DBI::Auth::Roles::TM,                #
            ]
        );
    }

    foreach my $path ( @acl_media_edit )
    {
        __PACKAGE__->allow_access_if_any(
            $path,
            [
                $MediaWords::DBI::Auth::Roles::MEDIA_EDIT,        #
                $MediaWords::DBI::Auth::Roles::TM,                #
            ]
        );
    }

    foreach my $path ( @acl_stories_edit )
    {
        __PACKAGE__->allow_access_if_any(
            $path,
            [
                $MediaWords::DBI::Auth::Roles::STORIES_EDIT,      #
                $MediaWords::DBI::Auth::Roles::TM,                #
            ]
        );
    }

    for my $path ( @acl_cm )
    {
        __PACKAGE__->allow_access_if_any(
            $path,
            [
                $MediaWords::DBI::Auth::Roles::TM,                #
                $MediaWords::DBI::Auth::Roles::TM_READONLY,       #
            ]
        );
    }

    for my $path ( @acl_search )
    {
        __PACKAGE__->allow_access_if_any( $path, [ $MediaWords::DBI::Auth::Roles::SEARCH ] );
    }

    # ---

    # All roles can access their profile
    __PACKAGE__->allow_access_if_any(
        '/admin/profile',
        [
            $MediaWords::DBI::Auth::Roles::ADMIN,             #
            $MediaWords::DBI::Auth::Roles::ADMIN_READONLY,    #
            $MediaWords::DBI::Auth::Roles::MEDIA_EDIT,        #
            $MediaWords::DBI::Auth::Roles::STORIES_EDIT,      #
            $MediaWords::DBI::Auth::Roles::TM,                #
            $MediaWords::DBI::Auth::Roles::STORIES_API,       #
            $MediaWords::DBI::Auth::Roles::SEARCH,            #
        ]
    );

    # Blanket rule for the rest of the administration controllers
    __PACKAGE__->deny_access_unless_any( "/admin",  [ $MediaWords::DBI::Auth::Roles::ADMIN ] );
    __PACKAGE__->deny_access_unless_any( "/search", [ $MediaWords::DBI::Auth::Roles::ADMIN ] );

    # Public interface
    __PACKAGE__->allow_access( "/login" );
    __PACKAGE__->allow_access( "/logout" );

    # we need to protect this with .htaccess until we can implement an easy to login via the api
    __PACKAGE__->allow_access( "/admin/stop_server" );

}

setup_acl();

# Checks if current user can visit a specified action
# (similar to can_visit() from Catalyst::ActionRole::ACL)
sub acl_user_can_visit
{
    my ( $self, $path ) = @_;

    my $action = $self->dispatcher->get_action_by_path( $path );

    if (    Scalar::Util::blessed( $action )
        and $action->name ne "access_denied"
        and $action->name ne "ACL error rethrower" )
    {
        eval { $self->_acl_engine->check_action_rules( $self, $action ) };

        if ( my $err = $@ )
        {
            return 0;
        }
        else
        {
            return 1;
        }
    }

    # Fallback
    return 0;
}

sub uri_for
{
    my ( $self, $path, $args ) = @_;

    if ( !$self->config->{ mediawords }->{ base_url } )
    {
        shift( @_ );
        return $self->SUPER::uri_for( @_ );
    }

    my $uri = URI->new( $self->config->{ mediawords }->{ base_url } . $path );

    if ( $args )
    {
        $uri->query_form( $args );
    }

    my $uri_string = $uri->as_string();

    while ( $uri_string =~ s~(https?\://.*)//~$1/~g ) { }

    return $uri_string;
}

sub create_form
{
    my ( $self, $args ) = @_;

    my $ret = HTML::FormFu::Unicode->new( $args );

    return $ret;
}

# Redirect unauthenticated users to login page
sub acl_access_denied
{
    my ( $c, $class, $action, $err ) = @_;

    if ( $c->user_exists )
    {
        $c->log->debug( 'User has been found, is not allowed to access page /' . $action );

        # Show the "unauthorized" message
        $c->res->body( 'You are not allowed to access page /' . $action );
        $c->res->status( 403 );
    }
    else
    {
        $c->log->debug( 'User not found, forwarding to /login' );

        # Redirect the user to the login page
        $c->response->redirect( $c->uri_for( '/login', { url => $c->req->uri } ) );
    }

    # Continue denying access
    return 0;
}

# shortcut to dbis model
sub dbis
{

    return $_[ 0 ]->model( 'DBIS' )->dbis( $_[ 0 ]->req );
}

=head1 NAME

MediaWords - Catalyst based application

=head1 SYNOPSIS

    script/mediawords_server.pl

=head1 DESCRIPTION

[enter your description here]

=head1 SEE ALSO

L<MediaWords::Controller::Root>, L<Catalyst>

=head1 AUTHOR

Hal Roberts

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;

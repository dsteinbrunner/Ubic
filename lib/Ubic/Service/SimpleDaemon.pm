package Ubic::Service::SimpleDaemon;

use strict;
use warnings;

# ABSTRACT: declarative service for daemonizing any binary

=head1 SYNOPSIS

    use Ubic::Service::SimpleDaemon;
    my $service = Ubic::Service::SimpleDaemon->new(
        bin => "sleep 1000",
        stdout => "/var/log/sleep.log",
        stderr => "/var/log/sleep.err.log",
        ubic_log => "/var/log/sleep.ubic.log",
        user => "nobody",
    );

=head1 DESCRIPTION

Use this class to daemonize any binary.

This module uses L<Ubic::Daemon> module for process daemonization. All pidfiles are stored in ubic data dir, with their names based on service names.

=cut

use parent qw(Ubic::Service::Skeleton);

use Cwd;
use Ubic::Daemon qw(start_daemon stop_daemon check_daemon);
use Ubic::Result qw(result);
use Ubic::Settings;
use File::Spec;

use Params::Validate qw(:all);

# Beware - this code will ignore any overrides if you're using custom Ubic->new(...) objects
our $PID_DIR;

sub _pid_dir {
    return $PID_DIR if defined $PID_DIR;
    if ($ENV{UBIC_DAEMON_PID_DIR}) {
        warn "UBIC_DAEMON_PID_DIR env variable is deprecated, use Ubic->set_data_dir or configs instead (see Ubic::Settings for details)";
        $PID_DIR = $ENV{UBIC_DAEMON_PID_DIR};
    }
    else {
        $PID_DIR = Ubic::Settings->data_dir."/simple-daemon/pid";
    }
    return $PID_DIR;
}

=head1 METHODS

=over

=item B<< new($params) >>

Constructor.

Parameters:

=over

=item I<bin>

Daemon binary.

=item I<user>

User under which daemon will be started. Optional, default is C<root>.

=item I<group>

Group under which daemon will be started. Optional, default is all user groups.

Value can be scalar or arrayref.

=item I<stdout>

File into which daemon's stdout will be redirected. Default is C</dev/null>.

=item I<stderr>

File into which daemon's stderr will be redirected. Default is C</dev/null>.

=item I<name>

Service's name.

Optional, will usually be set by upper-level multiservice. Don't set it unless you know what you're doing.

=back

=cut
sub new {
    my $class = shift;
    my $params = validate(@_, {
        bin => { type => SCALAR | ARRAYREF },
        user => { type => SCALAR, optional => 1 },
        group => { type => SCALAR | ARRAYREF, optional => 1 },
        name => { type => SCALAR, optional => 1 },
        stdout => { type => SCALAR, optional => 1 },
        stderr => { type => SCALAR, optional => 1 },
        ubic_log => { type => SCALAR, optional => 1 },
        cwd => { type => SCALAR, optional => 1 },
        env => { type => HASHREF, optional => 1 },
    });

    return bless {%$params} => $class;
}

=item B<< pidfile() >>

Get pid filename. It will be concatenated from simple-daemon pid dir and service's name.

=cut
sub pidfile {
    my ($self) = @_;
    my $name = $self->full_name or die "Can't start nameless SimpleDaemon";
    return _pid_dir."/$name";
}

sub start_impl {
    my ($self) = @_;

    my $old_cwd;
    if (defined $self->{cwd}) {
        $old_cwd = getcwd;
        chdir $self->{cwd} or die "chdir to '$self->{cwd}' failed: $!";
    }

    local %ENV = %ENV;
    if (defined $self->{env}) {
        for my $key (keys %{ $self->{env} }) {
            $ENV{$key} = $self->{env}{$key};
        }
    }

    my $start_params = {
        pidfile => $self->pidfile,
        bin => $self->{bin},
        stdout => $self->{stdout} || "/dev/null",
        stderr => $self->{stderr} || "/dev/null",
        ubic_log => $self->{ubic_log} || "/dev/null",
    };
    if ($old_cwd) {
        for my $key (qw/ pidfile stdout stderr ubic_log /) {
            next unless defined $start_params->{$key};
            $start_params->{$key} = File::Spec->rel2abs($start_params->{$key}, $old_cwd);
        }
    }
    start_daemon($start_params);

    if (defined $old_cwd) {
        chdir $old_cwd or die "chdir to '$old_cwd' failed: $!";
    }
}

sub user {
    my $self = shift;
    return $self->{user} if defined $self->{user};
    return $self->SUPER::user();
}

sub group {
    my $self = shift;
    my $groups = $self->{group};
    return $self->SUPER::group() if not defined $groups;
    return @$groups if ref $groups eq 'ARRAY';
    return $groups;
}

sub stop_impl {
    my ($self) = @_;
    stop_daemon($self->pidfile);
}

sub status_impl {
    my ($self) = @_;
    if (my $daemon = check_daemon($self->pidfile)) {
        return result('running', "pid ".$daemon->pid);
    }
    else {
        return result('not running');
    }
}

=back

=head1 SEE ALSO

L<Ubic::Daemon> - module to daemonize any binary

=cut

1;

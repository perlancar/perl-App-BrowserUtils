package App::BrowserUtils;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict 'subs', 'vars';
use warnings;
use Log::ger;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Utilities related to browsers, particularly modern GUI ones',
};

our %browsers = (
    firefox => {
        browser_fname_pat => qr/\A(Web Content|WebExtensions|firefox-bin)\z/,
    },
    chrome => {
        browser_fname_pat => qr/\A(chrome)\z/,
    },
    opera => {
        browser_fname_pat => qr/\A(opera)\z/,
    },
    vivaldi => {
        browser_fname_pat => qr/\A(vivaldi-bin)\z/,
    },
);

our %argopt_users = (
    users => {
        'x.name.is_plural' => 1,
        'x.name.singular' => 'user',
        summary => 'Kill browser processes that belong to certain user(s) only',
        schema => ['array*', of=>'unix::local_uid*'],
    },
);

our %argopt_quiet = (
    quiet => {
        schema => 'true*',
        cmdline_aliases => {q=>{}},
    },
);

our %args_common = (
    %argopt_users,
);

our $desc_pause = <<'_';

A modern browser now runs complex web pages and applications. Despite browser's
power management feature, these pages/tabs on the browser often still eat
considerable CPU cycles even though they only run in the background. Stopping
(kill -STOP) the browser processes is a simple and effective way to stop CPU
eating on Unix. It can be performed whenever you are not using your browsers for
a little while, e.g. when you are typing on an editor or watching a movie. When
you want to use your browser again, simply unpause it.

_

sub _do_browser {
    require Proc::Find;

    my ($which_action, $which_browser, %args) = @_;

    my $browser_fname_pat = $browsers{$which_browser}{browser_fname_pat}
        or return [400, "Unknown browser '$which_browser'"];

    my $procs = Proc::Find::find_proc(
        detail => 1,
        filter => sub {
            my $p = shift;

            if ($args{users} && @{ $args{users} }) {
                return 0 unless grep { $p->{uid} == $_ } @{ $args{users} };
            }
            return 0 unless $p->{fname} =~ $browser_fname_pat;
            log_trace "Found PID %d (cmdline=%s, fname=%s, uid=%d)", $p->{pid}, $p->{cmndline}, $p->{fname}, $p->{uid};
            1;
        },
    );

    my @pids = map { $_->{pid} } @$procs;

    if ($which_action eq 'ps') {
        return [200, "OK", $procs, {'table.fields'=>[qw/pid uid euid state/]}];
    } elsif ($which_action eq 'pause') {
        kill STOP => @pids;
        [200, "OK", "", {"func.pids" => \@pids}];
    } elsif ($which_action eq 'unpause') {
        kill CONT => @pids;
        [200, "OK", "", {"func.pids" => \@pids}];
    } elsif ($which_action eq 'terminate') {
        kill KILL => @pids;
        [200, "OK", "", {"func.pids" => \@pids}];
    } elsif ($which_action eq 'is_paused' || $which_action eq 'is_running') {
        my $num_stopped = 0;
        my $num_unstopped = 0;
        my $num_total = 0;
        for my $proc (@$procs) {
            $num_total++;
            if ($proc->{state} eq 'stop') { $num_stopped++ } else { $num_unstopped++ }
        }
        if ($which_action eq 'is_paused') {
            my $is_paused  = $num_total == 0 ? undef : $num_stopped == $num_total ? 1 : 0;
            my $msg = $num_total == 0 ? "There are NO $which_browser processes" :
                $num_stopped   == $num_total ? "$which_browser is paused (all processes are in stop state)" :
                $num_unstopped == $num_total ? "$which_browser is NOT paused (all processes are not in stop state)" :
                "$which_browser is NOT paused (some processes are not in stop state)";
            return [200, "OK", $is_paused, {
                'cmdline.exit_code' => $is_paused ? 0:1,
                'cmdline.result' => $args{quiet} ? '' : $msg,
            }];
        } else {
            my $is_running = $num_total == 0 ? undef : $num_unstopped > 0 ? 1 : 0;
            my $msg = $num_total == 0 ? "There are NO $which_browser processes" :
                $num_unstopped > 0 ? "$which_browser is running (some processes are not in stop state)" :
                "$which_browser exists but is NOT running (all processes are in stop state)";
            return [200, "OK", $is_running, {
                'cmdline.exit_code' => $is_running ? 0:1,
                'cmdline.result' => $args{quiet} ? '' : $msg,
            }];
        }
    } else {
        die "BUG: unknown command";
    }
}

$SPEC{ps_browsers} = {
    v => 1.1,
    summary => "List browser processes",
    args => {
        %args_common,
    },
};
sub ps_browsers {
    my %args = @_;

    my @rows;
    for my $browser (sort keys %browsers) {
        my $res = _do_browser('ps', $browser, %args);
        return $res unless $res->[0] == 200;
        push @rows, @{$res->[2]};
    }
    [200, "OK", \@rows];
}

$SPEC{pause_browsers} = {
    v => 1.1,
    summary => "Pause (kill -STOP) browsers",
    description => $desc_pause,
    args => {
        %args_common,
    },
};
sub pause_browsers {
    my %args = @_;

    my @pids;
    for my $browser (sort keys %browsers) {
        my $res = _do_browser('pause', $browser, %args);
        return $res unless $res->[0] == 200;
        push @pids, @{$res->[3]{'func.pids'}};
    }
    [200, "OK", undef, {"func.pids" => \@pids}];
}

$SPEC{unpause_browsers} = {
    v => 1.1,
    summary => "Unpause (resume, continue, kill -CONT) browsers",
    args => {
        %args_common,
    },
};
sub unpause_browsers {
    my %args = @_;

    my @pids;
    for my $browser (sort keys %browsers) {
        my $res = _do_browser('unpause', $browser, %args);
        return $res unless $res->[0] == 200;
        push @pids, @{$res->[3]{'func.pids'}};
    }
    [200, "OK", undef, {"func.pids" => \@pids}];
}

$SPEC{browsers_are_paused} = {
    v => 1.1,
    summary => "Check whether browsers are paused",
    description => <<'_',

Browser is defined as paused if *all* of its processes are in 'stop' state.

_
    args => {
        %args_common,
        %argopt_quiet,
    },
};
sub browsers_are_paused {
    my %args = @_;

    my $has_processes = 0;
    for my $browser (sort keys %browsers) {
        my $res = _do_browser('is_paused', $browser, %args);
        return $res unless $res->[0] == 200;
        return $res if defined $res->[2] && !$res->[2];
        $has_processes++ if defined $res->[2];
    }
    my $msg = !$has_processes ? "There are no browser processes" :
        "Browsers are paused (all processes are in stop state)";
    return [200, "OK", 1, {
        'cmdline.exit_code' => 0,
        'cmdline.result' => $args{quiet} ? '' : $msg,
    }];
}

$SPEC{terminate_browsers} = {
    v => 1.1,
    summary => "Terminate  (kill -KILL) browsers",
    args => {
        %args_common,
    },
};
sub terminate_browsers {
    my %args = @_;

    my @pids;
    for my $browser (sort keys %browsers) {
        my $res = _do_browser('terminate', $browser, %args);
        return $res unless $res->[0] == 200;
        push @pids, @{$res->[3]{'func.pids'}};
    }
    [200, "OK", undef, {"func.pids" => \@pids}];
}

1;
# ABSTRACT:

=head1 SYNOPSIS

=head1 DESCRIPTION

This distribution includes several utilities related to browsers:

#INSERT_EXECS_LIST

Supported browsers: Firefox on Linux, Opera on Linux, Chrome on Linux, and
Vivaldi on Linux.


=head1 SEE ALSO

Utilities using this distribution: L<App::FirefoxUtils>, L<App::ChromeUtils>,
L<App::OperaUtils>, L<App::VivaldiUtils>

L<App::BrowserOpenUtils>

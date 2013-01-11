use strict;
use Config;
use File::Spec;
use File::Basename qw(dirname);
use List::Util qw(first);

write_typemap( File::Spec->catfile('xs', 'typemap') );
write_magic_file( File::Spec->catfile('xs', 'mg-xs.inc') );

sub write_magic_file {
    my $file = shift;

    open my $fh, '>', $file or
        die "Could not open objects file $file: $!";

    print $fh <<EOM;
STATIC_INLINE
int
PerlZMQ_mg_free(pTHX_ SV * const sv, MAGIC *const mg ) {
    PERL_UNUSED_VAR(sv);
    Safefree(mg->mg_ptr);
    return 0;
}

STATIC_INLINE
int
PerlZMQ_mg_dup(pTHX_ MAGIC* const mg, CLONE_PARAMS* const param) {
    PERL_UNUSED_VAR(mg);
    PERL_UNUSED_VAR(param);
    return 0;
}

EOM

    my $file = "xs/perl_libzmq3.xs";
    open my $src, '<', $file or die "Failed to open $file: $!";
    my @perl_types = qw(
        ZMQ::LibZMQ3::Context
        ZMQ::LibZMQ3::Socket
        ZMQ::LibZMQ3::Message
    );
    foreach my $perl_type (@perl_types) {
        my $c_type = $perl_type;
        $c_type =~ s/::/_/g;
        $c_type =~ s/^ZMQ_LibZMQ3/PerlLibzmq3/;
        my $vtablename = sprintf '%s_vtbl', $c_type;

        # check if we have a function named ${c_type}_free and ${c_type}_mg_dup
        my ($has_free, $has_dup);
        seek ($src, 0, 0);
        while (<$src>) {
            $has_free++ if /^${c_type}_mg_free\b/;
            $has_dup++ if /^${c_type}_mg_dup\b/;
        }

        my $free = $has_free ? "${c_type}_mg_free" : "PerlZMQ_mg_free";
        my $dup  = $has_dup  ? "${c_type}_mg_dup"  : "PerlZMQ_mg_dup";
        print $fh <<EOM
static MGVTBL $vtablename = { /* for identity */
    NULL, /* get */
    NULL, /* set */
    NULL, /* len */
    NULL, /* clear */
    $free, /* free */
    NULL, /* copy */
    $dup, /* dup */
#ifdef MGf_LOCAL
    NULL  /* local */
#endif
};

EOM
    }

}

sub write_typemap {
    my $file = shift;

    my @perl_types = qw(
        ZMQ::LibZMQ3::Context
        ZMQ::LibZMQ3::Socket
        ZMQ::LibZMQ3::Message
    );

    open( my $out, '>', $file ) or
        die "Could not open $file for writing: $!";

    my (@decl, @input, @output);

    push @decl, "uint64_t T_UV";
    push @decl, "int64_t T_IV";

    foreach my $perl_type (@perl_types) {
        my $c_type = $perl_type;
        $c_type =~ s/::/_/g;
        $c_type =~ s/^ZMQ_LibZMQ3_/PerlLibzmq3_/;
        my $typemap_type = 'T_' . uc $c_type;

        my $closed_error = 
            $c_type =~ /Socket/ ? "ENOTSOCK" :
            "EFAULT"
        ;

        push @decl, "$c_type* $typemap_type";
        push @input, <<EOM;
$typemap_type
    P5ZMQ3_SV2STRUCT(\$arg, \$var, $perl_type, $c_type, $closed_error);
EOM
        push @output, <<EOM;
$typemap_type
    P5ZMQ3_STRUCT2SV(\$arg, \$var, $perl_type, $c_type);
EOM
    }

    print $out
        "# Do NOT edit this file! This file was automatically generated\n",
        "# by Makefile.PL on @{[scalar localtime]}. If you want to\n",
        "# regenerate it, remove this file and re-run Makefile.PL\n",
        "\n"
    ;
    print $out join( "\n",
        "TYPEMAP\n",
        join("\n", @decl), 
        "\n",
        "INPUT\n",
        join("\n", @input),
        "\n",
        "OUTPUT\n",
        join("\n", @output),
        "\n",
    );

    close $out;
}


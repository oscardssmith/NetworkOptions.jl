export ca_roots, ca_roots_path

"""
    ca_roots() :: Union{Nothing, String}

The `ca_roots()` function tells the caller where, if anywhere, to find a file or
directory of PEM-encoded certificate authority roots. By default, on systems
like Windows and macOS where the built-in TLS engines know how to verify hosts
using the system's built-in certificate verification mechanism, this function
will return `nothing`. On classic UNIX systems (excluding macOS), root
certificates are typically stored in a file in `/etc`: the common places for the
current UNIX kernel will be searched and if one of these paths exists, it will
be returned; if none of these typical root certificate paths exist, then the
path to the set of root certificates that are bundled with Julia is returned.

The default value returned by `ca_roots()` may be overridden by setting the
`JULIA_SSL_CA_ROOTS_PATH` environment variable to a non-empty value, in which
case this function will always return that path (whether it exists or not).
"""
ca_roots()::Union{Nothing,String} = _ca_roots(true)

"""
    ca_roots_path() :: String

The `ca_roots_path()` function is similar to the `ca_roots()` function except
that it always returns a path to a file or directory of PEM-encoded certificate
authority roots. When called on a system like Windows or macOS, where system
root certificates are not stored in the file system, it will currently return
the path to the set of root certificates that are bundled with Julia. (In the
future, this function may instead extract the root certificates from the system
and save them to a file whose path would be returned.)

If it is possible to configure a library that uses TLS to use the system
certificates that is generally preferrable: i.e. it is better to use
`ca_roots()` which returns `nothing` to indicate that the system certs should be
used. The `ca_roots_path()` function should only be used when configuring
libraries which _require_ a path to a file or directory for root certificates.

The default value returned by `ca_roots_path()` may be overridden by setting the
`JULIA_SSL_CA_ROOTS_PATH` environment variable to a non-empty value, in which
case this function will always return that path (whether it exists or not).
"""
ca_roots_path()::String = _ca_roots(false)

# NOTE: this has to be a function not a constant since the
# value of Sys.BINDIR changes from build time to run time.
bundled_ca_roots() =
    normpath(Sys.BINDIR::String, "..", "share", "julia", "cert.pem")

const LINUX_CA_ROOTS = [
    "/etc/ssl/cert.pem"								    # Alpine Linux
    "/etc/ssl/ca-bundle.pem"			                # OpenSUSE
    "/etc/ssl/certs/ca-certificates.crt"                # Debian/Ubuntu/Gentoo etc.
    "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"	# CentOS/RHEL 7
    "/etc/pki/tls/certs/ca-bundle.crt"	                # Fedora/RHEL 6
    "/etc/pki/tls/cacert.pem"			                # OpenELEC
]

const BSD_CA_ROOTS = [
    "/etc/ssl/cert.pem"                                 # OpenBSD
    "/usr/local/share/certs/ca-root-nss.crt"            # FreeBSD
    "/usr/local/etc/ssl/cert.pem"                       # FreeBSD
]

const SYSTEM_CA_ROOTS_LOCK = ReentrantLock()
const SYSTEM_CA_ROOTS = Ref{String}()

function system_ca_roots()
    lock(SYSTEM_CA_ROOTS_LOCK) do
        isassigned(SYSTEM_CA_ROOTS) && return
        search_path = Sys.islinux() ? LINUX_CA_ROOTS :
            Sys.isbsd() && !Sys.isapple() ? BSD_CA_ROOTS : String[]
        for path in search_path
            ispath(path) || continue
            SYSTEM_CA_ROOTS[] = path
            return
        end
        # TODO: extract system certs on Windows & macOS
        SYSTEM_CA_ROOTS[] = bundled_ca_roots()
    end
    return SYSTEM_CA_ROOTS[]
end

function _ca_roots(allow_nothing::Bool)
    path = get(ENV, "JULIA_SSL_CA_ROOTS_PATH", nothing)
    path !== nothing && !isempty(path) && return path
    allow_nothing && (Sys.iswindows() || Sys.isapple()) && return nothing
    return system_ca_roots()
end

function getindex(itp::GriddedInterpolation{T,N,TCoefs,Interpolations.Gridded{Interpolations.Cubic{Interpolations.Reflect}},K,P}, x::Number) where{T,N,TCoefs,K,P}
    a,b,c = coefficients(itp.knots[1], itp.coefs)
    interpolate(x, a, b, c, itp.knots[1], itp.coefs)
end

function getindex(itp::GriddedInterpolation{T,N,TCoefs,Interpolations.Gridded{Interpolations.Cubic{Interpolations.Reflect}},K,P}, x::AbstractVector) where{T,N,TCoefs,K,P}
    a,b,c = coefficients(itp.knots[1], itp.coefs)
    interpolate.(x, [a], [b], [c], [itp.knots[1]], [itp.coefs])
end


"""
    interpolate(x, a, b, c, X, Y, v=false)
Interpoalte at location x using coefficients a,b,c fitted to X & Y.
If i in in the range of x:
    Sᵢ(x) = a(x - xᵢ)³ + b(x - xᵢ)² + c(x - xᵢ) + dᵢ
Otherwise extrapolate with a = 0 (i.e. a 1st or 2nd order spline)
"""
function interpolate(x, a, b, c, X, Y, v=false)
    idx = max(searchsortedfirst(X,x)-1,1)
    h   = x - X[idx] # (x - xᵢ)
    n   = length(X)
 
    if x < X[1]        # extrapolation to the left
        return (b[1]*h + c[1])*h + Y[1];
    elseif x > X[n]       # extrapolation to the right
        return (b[n]*h + c[n])*h + Y[n];
    else                    # interpolation
        return ((a[idx]*h + b[idx])*h + c[idx])*h + Y[idx];
    end
    interpol
end


function coefficients(x, y;
        x1 = 0.,
        xend = 0.,
        m_force_linear_extrapolation = true,
        boundaries = (:first_deriv, :first_deriv)
    )
    n   = length(x)
    A   = zeros(n,n)
    rx  = zeros(n)
    for i in 2:(n-1)
        A[i-1,i]  = 1.0/3.0*(x[i]-x[i-1]);
        A[i,i]    = 2.0/3.0*(x[i+1]-x[i-1]);
        A[i+1,i]  = 1.0/3.0*(x[i+1]-x[i]);
        rx[i]  = (y[i+1]-y[i])/(x[i+1]-x[i]) - (y[i]-y[i-1])/(x[i]-x[i-1])
    end
    
	boundary_start,boundary_end = boundaries
    if (boundary_start == :second_deriv)
        A[1,1] = 2.0;
        A[2,1] = 0.0;
        rx[0] = x1;
    elseif (boundary_start == :first_deriv)
        A[1,1] = 2.0*(x[2]-x[1]);
        A[2,1] = 1.0*(x[2]-x[1]);
        rx[1] = 3.0*((y[2]-y[1])/(x[2]-x[1])-x1);
    else
        assert(false);
    end
    
    if (boundary_end == :second_deriv)
    A[n,n] = 2.0;
    A[n-1,n] = 0.0;
    rx[n] = xend;
    elseif (boundary_end == :first_deriv)
        A[n,n] = 2.0*(x[n]-x[n-1]);
        A[n-1,n] =1.0*(x[n]-x[n-1]);
        rx[n]=3.0*(xend-(y[n]-y[n-1])/(x[n]-x[n-1]));
    end

    b = A \ rx;

    a = zeros(n)
    c = zeros(n)
    for i in 1:(n-1)
        a[i]=1.0/3.0*(b[i+1]-b[i])/(x[i+1]-x[i])
        c[i]=(y[i+1]-y[i])/(x[i+1]-x[i])- 1.0/3.0*(2.0*b[i]+b[i+1])*(x[i+1]-x[i])
    end

    b[1] = (m_force_linear_extrapolation==false) ? b[1] : 0.0;
    h      = x[n]-x[n-1];
    a[n] = 0.0
    c[n] = 3a[n-1] * (h * h)  +  2b[n-1] * h  +  c[n-1]
    m_force_linear_extrapolation && (b[n]=0.0)
    return a, b, c
end

#####

function define_indices_d(::Type{Gridded{Cubic{Reflect}}}, d, pad)
    symix, symixp, symx = Symbol("ix_",d), Symbol("ixp_",d), Symbol("x_",d)
    quote
        $symix = clamp($symix, 1, size(itp, $d)-1)
        $symixp = $symix + 1
    end
end

function coefficients(::Type{Gridded{Cubic{Reflect}}}, N, d)
    symix, symixp, symx = Symbol("ix_",d), Symbol("ixp_",d), Symbol("x_",d)
    sym, symp, symfx = Symbol("c_",d), Symbol("cp_",d), Symbol("fx_",d)
    symk, symkix = Symbol("k_",d), Symbol("kix_",d)
    quote
        $symkix = $symk[$symix]
        $symfx = ($symx - $symkix)/($symk[$symixp] - $symkix)
        $sym = 1 - $symfx
        $symp = $symfx
    end
end

function gradient_coefficients(::Type{Gridded{Cubic{Reflect}}}, d)
    sym, symp = Symbol("c_",d), Symbol("cp_",d)
    symk, symix = Symbol("k_",d), Symbol("ix_",d)
    symixp = Symbol("ixp_",d)
    quote
        $symp = 1/($symk[$symixp] - $symk[$symix])
        $sym = - $symp
    end
end

# This assumes fractional values 0 <= fx_d <= 1, integral values ix_d and ixp_d (typically ixp_d = ix_d+1,
#except at boundaries), and an array itp.coefs
function index_gen(::Type{Gridded{Cubic{Reflect}}}, ::Type{IT}, N::Integer, offsets...) where IT<:DimSpec{Gridded}
    if length(offsets) < N
        d = length(offsets)+1
        sym = Symbol("c_", d)
        symp = Symbol("cp_", d)
        return :($sym * $(index_gen(IT, N, offsets..., 0)) + $symp * $(index_gen(IT, N, offsets..., 1)))
    else
        indices = [offsetsym(offsets[d], d) for d = 1:N]
        return :(itp.coefs[$(indices...)])
    end
end

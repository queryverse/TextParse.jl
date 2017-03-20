#!/bin/sh

julia << EOF

Pkg.add("PooledArrays")
Pkg.checkout("PooledArrays")
Pkg.checkout("PooledArrays", "s/abstractarray-refs")

EOF

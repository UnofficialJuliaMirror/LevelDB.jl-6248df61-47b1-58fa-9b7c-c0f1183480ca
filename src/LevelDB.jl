module LevelDB

using BinDeps
using Pkg

depsfile = Pkg.dir("LevelDB","deps","deps.jl")
if isfile(depsfile)
    include(depsfile)
else
    error("LevelDB not properly installed. Please run Pkg.build(\"LevelDB\")")
end

export open_db
export close_db
export create_write_batch
export batch_put
export write_batch
export db_put
export db_get
export db_delete
export db_range
export range_close


function open_db(file_path, create_if_missing)
    options = ccall( (:leveldb_options_create, libleveldbjl), Ptr{Cvoid}, ())
    if create_if_missing
        ccall( (:leveldb_options_set_create_if_missing, libleveldbjl), Cvoid,
              (Ptr{Cvoid}, UInt8), options, 1)
    end
    err = Ptr{UInt8}[0]
    db = ccall( (:leveldb_open, libleveldbjl), Ptr{Cvoid},
               (Ptr{Cvoid}, Ptr{UInt8}, Ptr{Ptr{UInt8}}) , options, file_path, err)

    if db == C_NULL
        error(String(err[1]))
    end
    return db
end


function close_db(db)
    ccall( (:leveldb_close, libleveldbjl), Cvoid, (Ptr{Cvoid},), db)
end

function db_put(db, key, value, val_len)
    options = ccall( (:leveldb_writeoptions_create, libleveldbjl), Ptr{Cvoid}, ())
    err = Ptr{UInt8}[0]
    ccall( (:leveldb_put, libleveldbjl), Cvoid,
          (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{UInt8}, UInt, Ptr{UInt8}, UInt, Ptr{Ptr{UInt8}} ),
          db, options,key, length(key), value, val_len, err)
    if err[1] != C_NULL
        error(String(err[1]))
    end
end

# return an UInt8 array obj
function db_get(db, key)
    # leveldb_get will allocate the buffer for return value
    options = ccall( (:leveldb_readoptions_create, libleveldbjl), Ptr{Cvoid}, ())
    err = Ptr{UInt8}[0]
    val_len = Csize_t[0]
    value = ccall( (:leveldb_get, libleveldbjl), Ptr{UInt8},
          (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{UInt8}, UInt, Ptr{Csize_t},  Ptr{Ptr{UInt8}} ),
          db, options, key, length(key), val_len, err)
    if err[1] != C_NULL
        error(String(err[1]))
    else
        s = unsafe_wrap(Array{UInt8,1},value, val_len[1], true)
        s
    end
end

function db_delete(db, key)
    options = ccall( (:leveldb_writeoptions_create, libleveldbjl), Ptr{Cvoid}, ())
    err = Ptr{UInt8}[0]
    ccall( (:leveldb_delete, libleveldbjl), Cvoid,
          (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{UInt8}, UInt, Ptr{Ptr{UInt8}} ),
          db, options, key, length(key), err)
    if err[1] != C_NULL
        error(String(err[1]))
    end
end


function create_write_batch()
    batch = ccall( (:leveldb_writebatch_create, libleveldbjl), Ptr{Cvoid},())
    return batch
end



function batch_put(batch, key, value, val_len)
    ccall( (:leveldb_writebatch_put, libleveldbjl), Cvoid,
          (Ptr{UInt8}, Ptr{UInt8}, UInt, Ptr{UInt8}, UInt),
          batch, key, length(key), value, val_len)
end

function write_batch(db, batch)
    options = ccall( (:leveldb_writeoptions_create, libleveldbjl), Ptr{Cvoid}, ())
    err = Ptr{UInt8}[0]
    ccall( (:leveldb_write, libleveldbjl), Cvoid,
          (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid},  Ptr{Ptr{UInt8}} ),
          db, options, batch, err)
    if err[1] != C_NULL
        error(unsafe_string(err[1])) 
    end
end



function create_iter(db::Ptr{Cvoid}, options::Ptr{Cvoid})
  ccall( (:leveldb_create_iterator, libleveldbjl), Ptr{Cvoid},
              (Ptr{Cvoid}, Ptr{Cvoid}),
              db, options)
end

function iter_valid(it::Ptr{Cvoid})
    valid = ccall( (:leveldb_iter_valid, libleveldbjl), UInt8, (Ptr{Cvoid},),  it)
    valid  == 1
end

function iter_key(it::Ptr{Cvoid})
    k_len = Csize_t[0]
    key = ccall( (:leveldb_iter_key, libleveldbjl), Ptr{UInt8},
                (Ptr{Cvoid}, Ptr{Csize_t}),  it, k_len)
    k = unsafe_wrap(Array{UInt8,1},  key, k_len[1], false)
    x = String(k)
    #print(x)
    x
end

function iter_value(it::Ptr{Cvoid})
  v_len = Csize_t[0]
  value = ccall( (:leveldb_iter_value, libleveldbjl), Ptr{UInt8},
    (Ptr{Cvoid}, Ptr{Csize_t}),   it, v_len)
   v = unsafe_wrap(Array{UInt8,1}, value, (v_len[1],), false)
   #print("\n val ", v)
   v
end

function iter_seek(it::Ptr{Cvoid}, key)
  ccall( (:leveldb_iter_seek, libleveldbjl), Cvoid,
    (Ptr{Cvoid}, Ptr{UInt8}, UInt),
    it, key, length(key))
end

function iter_next(it::Ptr{Cvoid})
  ccall( (:leveldb_iter_next, libleveldbjl), Cvoid,
    (Ptr{Cvoid},),
    it)
end

struct Range
  iter::Ptr{Cvoid}
  options::Ptr{Cvoid}
  key_start::AbstractString
  key_end::AbstractString
  destroyed::Bool
end

function db_range(db, key_start, key_end="\uffff")
  options = ccall( (:leveldb_readoptions_create, libleveldbjl), Ptr{Cvoid}, ())
  iter = create_iter(db, options)
  Range(iter, options, key_start, key_end, false)
end

function range_close(range::Range)
  if !range.destroyed
    range.destroyed = true
    ccall( (:leveldb_iter_destroy, libleveldbjl), Cvoid,
      (Ptr{Cvoid},),
      range.iter)
    ccall( (:leveldb_readoptions_destroy, libleveldbjl), Cvoid,
      (Ptr{Cvoid},),
      range.options)
  end
end

function start(range::Range)
  iter_seek(range.iter, range.key_start)
end

function done(range::Range, state=Union{})
    if range.destroyed
        return true
    end

    #print("\n------------ READ next key ---")
    it_valid = iter_valid(range.iter)
    if !it_valid
        isdone = true
   else
        key = iter_key(range.iter)
        isdone =  key > range.key_end
    end
    if isdone
        range_close(range)
    end

    isdone
end

function next(range::Range, state=Union{})
  k = iter_key(range.iter)
  v = iter_value(range.iter)
  iter_next(range.iter)
  ((k, v), Union{})
end


end

#!/usr/bin/env julia

if !isdefined(Main, :Revise)
	const includet = include
end

includet("templates.jl")

cd(dirname(@__FILE__))




"""
Infer the type or kind of a note by which file extensions are present.
For example, a pair of `*.tex` and `*.pdf` files with the same name form a LaTeX note.
"""
function notekind(byext::Dict{Symbol,String})

	combos = Dict(
		Set([:typ, :pdf]) => :typst_pdf,
		Set([:tex, :pdf]) => :latex_pdf,
		Set([:jl, :html]) => :pluto_notebook,
		Set([:jl]) => :julia_code,
	)

	if keys(byext) in keys(combos)
		combos[keys(byext)]
	else
		@error "Can't recognise multi-file note" byext
	end

end

function findnotes(srcdir)
	notefiles = Dict{String,Dict{Symbol,String}}()
	notedirs = Dict{String,Vector{String}}()

	for (root, dirs, files) in walkdir(srcdir)
		filter!(!startswith("."), files)
		for file in files

			m = match(r"^(.*)\.note\.(\w+)$", file)
			isnothing(m) && continue
			name, ext = m
			path = joinpath(root, file)

			if name ∉ keys(notefiles)
				notefiles[name] = Dict()
			end
			notefiles[name][Symbol(ext)] = path

			if name ∉ keys(notedirs)
				notedirs[name] = splitpath(chopprefix(root, srcdir))
			end
		end
	end

	if length(notefiles) == 0
		@info "Debug info" pwd() readdir()
		error("Found no notes")
	end

	notekinds = Dict(name => notekind(byext) for (name, byext) in notefiles)


	Dict(
		name => (
			name=name,
			dir=notedirs[name],
			kind=notekinds[name],
			files=notefiles[name],
		)
		for name in keys(notefiles)
	)
end



function totree(notes::Dict)
	paths = [(name => info) => info.dir for (name, info) in notes]
	flattenned = sort!(paths, by=last)
	totree(flattenned)
end

function totree(nodes::AbstractVector)
	tree = "root" => []
	stack = [tree]
	for (node, path) in nodes

		i = 1
		while i < min(length(path) + 1, length(stack))
			path[i] == stack[i + 1].first || break
			i += 1
		end

		while length(stack) > i
			pop!(stack)
		end

		while length(stack) <= length(path)
			subtree = path[length(stack)] => []
			push!(stack[end].second, subtree)
			push!(stack, subtree)
		end

		push!(stack[end].second, node)

	end
	tree.second
end



"""
Make a link of the source file in current directory,
with `.note.` removed from the filename.
"""
function tohere(srcfile::String)
	dest = replace(basename(srcfile), ".note."=>".")
	run(`ln $srcfile $dest`)
	dest
end


template(::Val{:typst_pdf}, n) = Templates.pdf(n)
template(::Val{:latex_pdf}, n) = Templates.pdf(n)
template(::Val{:pluto_notebook}, n) = Templates.html(n)
template(::Val{:julia_code}, n) = Templates.code(n, read(n.files[:jl], String), :julia)
template(::Val, n) = @warn "Skipping note" n

function rendernote(note::NamedTuple)
	# copy files into site directory
	for (ext, file) in note.files
		ext == :html && continue
		note.files[ext] = tohere(file)
	end

	open("$(note.name).html", "w") do f
		html = template(Val(note.kind), note)
		write(f, html)
	end
end


function exportpermalinks(notes, dest="permalinks.csv")
	open(dest, "w") do file
		for name in sort!(collect(keys(notes)))
			write(file, name, ",", Templates.permalink(name), "\n")
		end
	end
end


function build(srcdir, targetdir)
	srcdir = abspath(expanduser(srcdir))
	targetdir = abspath(expanduser(targetdir))
	@info "Building Zettelkasten" srcdir targetdir


	rm(targetdir, recursive=true, force=true)
	mkpath(targetdir)

	cp("assets", joinpath(targetdir, "assets"))

	notes = findnotes(srcdir)

	cd(targetdir) do
		# index page
		tree = reduce(vcat, last.(totree(notes)))
		open("index.html", "w") do f
			write(f, Templates.toc(tree))
		end

		# individual notes
		for (name, note) in notes
			println("Rendering note ", repr(name))
			rendernote(note)
		end
	end

	# exportpermalinks(notes, joinpath(targetdir, "permalinks.csv"))

	nothing
end


if !isinteractive()
	if length(ARGS) != 2
		error("""Command line usage:
		./build.jl source_directory build_directory
		  source_directory: Path to notes directory
		  build_directory: Destination path for static site
		""")
	end
	sourcedir = ARGS[1]
	targetdir = ARGS[2]
	build(sourcedir, targetdir)
end

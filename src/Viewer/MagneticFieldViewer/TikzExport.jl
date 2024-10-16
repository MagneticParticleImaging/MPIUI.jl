# Functions with tex-code to build up the entire file

# combine tikz into final tex file
function exportTikz(filename::String, cmin, cmax, discr::Int, arrowL::Int, radius, L::Int)

    # get all tex-stuff
    texPre, texPost = prepareTex() # tex stuff around tikzfigure
    tikzParams = setTikzParams(filename,cmin,cmax,discr,arrowL,radius,L) # parameter defined in the viewer
    tikzConfig = prepareTikzConfig() # plot configurations
    tikzPlot = prepareTikzPlot() # plotting stuff

    # build tikzfigure
    tikz = prepareTikz(tikzConfig, tikzPlot)

    # final tex file
    tex = texPre * tikzParams * tikz * texPost

    return tex

end

# prepare tex stuff around tikzfigure
function prepareTex()

    texPre = """
    \\documentclass{standalone}
    \\standaloneconfig{border=-1.0cm 0.0cm 0.0cm 0cm} % cut off unnecessary spaces (left, ...)

    % tikz & pgfplots
    \\usepackage{tikz}
    \\usepackage{pgfplots}
    \\pgfplotsset{compat=newest}

    \\usetikzlibrary{positioning, backgrounds, fit, calc}
    \\usepgfplotslibrary{units}
    \\usepgfplotslibrary{groupplots} % positioning of the plots

    \\pgfdeclarelayer{background}
    \\pgfdeclarelayer{foreground}
    \\pgfsetlayers{background,main,foreground}

    % Coefficients plot
    \\pgfplotsset{
        unit markings=slash space,
        /pgfplots/xbar/.style={
        /pgf/bar shift={-0.5*(\\numplotsofactualtype*\\pgfplotbarwidth + (\\numplotsofactualtype-1)*#1) + (.5+\\plotnumofactualtype)*\\pgfplotbarwidth + \\plotnumofactualtype*#1},
        },
    }
    % Style to select only points from #1 to #2 (inclusive)
    \\pgfplotsset{select coords between index/.style 2 args={
        x filter/.code={
            \\ifnum\\coordindex<#1\\def\\pgfmathresult{}\\fi
            \\ifnum\\coordindex>#2\\def\\pgfmathresult{}\\fi
        }
    }}

    %% Colors
    \\definecolor{ibidark}{RGB}{0,73,146}	% blue
    \\definecolor{ukesec1}{RGB}{255,223,0}	% yellow
    \\definecolor{ukesec4}{RGB}{138,189,36}	% green


    \\usepackage{bm, amsmath, amssymb}

    \\begin{document}
    """

    texPost = """
    \\end{document}
    """

    return texPre, texPost

end

# set all necessary parameter
function setTikzParams(filename,cmin,cmax,discr,arrowL,radius,L)

    tikzParams = """
    % data path
    \\def\\pathFile{$(filename)}

    % define sizes
    \\def\\h{5cm}
    \\def\\w{3.88*\\h}
    \\def\\arrowLength{$(arrowL)}
    \\pgfmathsetmacro\\scaleArrow{0.04*\\arrowLength}
    \\pgfmathsetmacro\\vsep{1cm}  % vertical separation between subplots
    \\pgfmathsetmacro\\hsep{1.3cm}  % horizontal separation between subplots

    % define some field-specific stuff
    \\def\\cmin{$(cmin)} % field plot
    \\def\\cmax{$(cmax)} % field plot
    \\def\\discr{$(discr)} % discretization
    \\def\\radius{$(radius)}
    \\def\\L{$(L)}

    \\pgfmathsetmacro\\maxTick{(\\L+1)^2+0.5}
    """

    return tikzParams
end


# prepare plot configurations 
function prepareTikzConfig()

    tikzConfig = """
    % data
    \\pgfplotstableread[col sep=comma,]{\\pathFile_field.csv}\\datatableField % load data
    \\pgfplotstableread[col sep=comma,]{\\pathFile_field_quiver.csv}\\datatableQuiver % load data
    \\pgfplotstableread[col sep=semicolon,]{\\pathFile_coeffs.csv}\\datatableCoeffs % load data

    % coefficients: xlabel
    \\gdef\\labellist{}
    \\foreach \\l in {0,1,...,\\L} {
        \\foreach \\m in {-\\l,...,\\l} {
            \\xdef\\labellist{\\labellist {[\\l,\\m]},}
        }
    }
    \\edef\\temp{\\noexpand\\pgfplotsset{x tick labels list/.style={xticklabels={\\labellist}}}}%
    \\temp

    %% Setup of the plots
    \\pgfplotsset{
        field/.style={
            clip mode=individual,
            height=\\h, width=\\h,
            axis equal image, 
            %%
            view={0}{90},
            point meta = explicit,
            %%%
            mesh/cols=\\discr,
            %% ticks %%
                tick align=outside,
                tickpos=left,
                tick style={/pgfplots/major tick length=3pt},
                x tick label style={yshift=1pt}, y tick label style={xshift=1pt},
            %% labels %%
                change x base = true, change y base = true,
                ylabel={\$z\$},
                xlabel={\$x\$},
                x unit = m, x SI prefix = milli,
                y unit = m, y SI prefix = milli,
                xlabel shift={-6pt},
                ylabel shift={-5pt},
            %% Colors %%
                colormap/viridis,
                shader=interp,
            %% Colorbar:
                point meta min=\\cmin,
                point meta max=\\cmax,
                small,
                colorbar style={
                    %% sizes %%
                    colorbar shift/.style={xshift=0.075*\\h},
                    footnotesize,        
                    width=0.3cm,
                    height=1.12*\\h,
                    %% ticks %%
                    xticklabel style = {xshift=0.0cm,yshift=0.0cm},
                    x tick style= {color=black},
                    extra x tick style={tickwidth=0pt},
                    change y base = true,
                    %% label %%
                    ylabel = {\$\\lVert \\bm B \\rVert_2\$},
                    y unit = T, y SI prefix = milli,
                    unit markings=slash space,
                    ylabel style={rotate=180}
                },
        },
        coeffs/.style = {
            set layers=standard,
            footnotesize,
            width=\\w,
            height=\\h,
            % select only part of the coefficients
            select coords between index={0}{15},
            %% labels %%
                change y base = true,
                xlabel={\$[l,m]\$},
                ylabel={coefficients},
                y unit = T, %m^{-\\mathnormal{l}}, % mathnormal for italic l
                y SI prefix = milli,
                xlabel shift={2pt},
                ylabel shift={-8pt},
                label style={font=\\small},
            %% ticks %%
                scaled y ticks=base 10:3, % quasi milliTesla Angabe
                scaled ticks=false,  % ohne einzelnes 10^-2
                tick label style={/pgf/number format/fixed,}, % einzelne konkrete ticks label
                %                 font=\\tiny},
                tick style={major grid style={thin,dotted,gray}},
                tick align=outside,%center,
                tickpos=left,
                x tick labels list,
                % label as interval for 3 bars each
                    xtick={0.5,1.5,...,\\maxTick},
                    x tick label as interval,
                    enlarge x limits=0.05,
                tick style={/pgfplots/major tick length=3pt},
                x tick label style={yshift=1pt}, y tick label style={xshift=1pt},
                %% grid %%
                    grid=major,
                    extra y ticks={0.0}, % black line for y = 0
                    extra y tick labels={},
                    extra x tick style={major grid style={thin,gray}},
                    extra y tick style={major grid style={solid,black,on layer=axis foreground}}, % black line for y = 0
            %% legend %%
                legend style = {anchor=north east, at={(0.9925,0.975)}},
                legend columns=1,
        },
        sphere/.style = {color=white, dashed, very thick,outer sep=2pt}, % measured sphere
        }
    """

    return tikzConfig

end

# prepare plotting stuff
function prepareTikzPlot()

    tikzPlot = """
    %% Plot
    \\begin{groupplot}[
        group style={
           group size=3 by 2,
           vertical sep=\\vsep,
           horizontal sep=\\hsep,
           },
        height=\\h,
        width=\\h,
        scale only axis]
    
    %%% Magnetic fields
    % xz-plane
    \\nextgroupplot[field,
                   % title
                   title = {\$xz\$-plane},
                   title style = {yshift=-5pt},
                   ]
        % norm
        \\addplot3[surf] table [x=PlaneXZ_x,y=PlaneXZ_z,meta=PlaneXZ_f] {\\datatableField};
        % arrows
        \\addplot[
            quiver = {
                u = \\thisrow{PlaneXZ_u},
                v = \\thisrow{PlaneXZ_v},
                scale arrows = \\scaleArrow,
                update limits=false,
            },
            -stealth,
            ] 
            table [x=PlaneXZ_x,y=PlaneXZ_z, ] {\\datatableQuiver};
        % circle
        \\addplot [domain=-180:180, sphere] ({\\radius*cos(x)},{\\radius*sin(x)});
    
    % yz-plane
    \\nextgroupplot[field, 
                   xlabel={\$y\$}, ylabel={\$z\$},
                   % title
                   title = {\$yz\$-plane},
                   title style = {yshift=-5pt},
                   ]
        % norm
        \\addplot3[surf] table [x=PlaneYZ_y,y=PlaneYZ_z,meta=PlaneYZ_f] {\\datatableField};
        % arrows
        \\addplot[
            quiver = {
                u = \\thisrow{quiver_yzu}, % u=PlaneXZ_u 
                v = \\thisrow{quiver_yzv}, % v=PlaneXZ_v
                scale arrows = \\scaleArrow,
                update limits=false,
            },
            -stealth,
            ] 
            table [x=PlaneYZ_y,y=PlaneYZ_z, ] {\\datatableQuiver};
        % circle
        \\addplot [domain=-180:180, sphere] ({\\radius*cos(x)},{\\radius*sin(x)});
    
    % xy-plane
    \\nextgroupplot[field, 
                   xlabel={\$x\$}, ylabel={\$y\$},
                   % title
                   title = {\$xy\$-plane},
                   title style = {yshift=-5pt},
                   % colorbar
                   colorbar,
                   ]
        % field
        \\addplot3[surf] table [x=PlaneXY_x,y=PlaneXY_y,meta=PlaneXY_f] {\\datatableField};
        % arrows
        \\addplot[
            quiver = {
                u = \\thisrow{Xyu}, % u=PlaneXZ_u 
                v = \\thisrow{Xyv}, % v=PlaneXZ_v 
                scale arrows = \\scaleArrow,
                update limits=false,
            },
            -stealth,
            ] 
            table [x=PlaneXY_y,y=PlaneXY_x, ] {\\datatableQuiver};
        % circle
        \\addplot [domain=-180:180, sphere] ({\\radius*cos(x)},{\\radius*sin(x)});
    
    \\nextgroupplot[group/empty plot]
    
    %% Coefficients %%
    \\nextgroupplot[coeffs,
                   % bar plot
                   ybar=1pt,
                   bar width=4.0pt,
                   ]
    
        \\addplot[fill = ibidark,draw=none] table [x = num, y = x] {\\datatableCoeffs}; % x
        \\addlegendentry{\$x\$}
        \\addplot[fill=ukesec4,draw=none] table [x = num, y = y] {\\datatableCoeffs}; % y
        \\addlegendentry{\$y\$}
        \\addplot[fill=ukesec1,draw=none] table [x = num, y = z] {\\datatableCoeffs}; % z
        \\addlegendentry{\$z\$}
    
    \\nextgroupplot[group/empty plot]   
    
    \\end{groupplot}
    """

    return tikzPlot

end

# prepare complete tikzpicture
function prepareTikz(tikzConfig, tikzPlot)

    tikzPre = """
    \\begin{tikzpicture}
    """

    tikzPost = """
    \\end{tikzpicture}
    """

    tikz = tikzPre * tikzConfig * tikzPlot * tikzPost

    return tikz

end
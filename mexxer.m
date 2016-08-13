function [lhs,rhs] = mexxer(filename)
%MEXXER Create template/interface of C code from MATLAB file.
%   MEXXER(FILENAME) generates C code from .m file FILENAME.

% Copyright (C) 2016 Luigi Acerbi
%
% This software is distributed under the GNU General Public License 
% (version 3 or later); please refer to the file LICENSE.txt, included with 
% the software, for details.

%   Author:     Luigi Acerbi
%   Email:      luigi.acerbi@gmail.com
%   Version:    14/Aug/2016 (beta)

% Open input file
[~,name,ext] = fileparts(filename);
if isempty(ext); ext = '.m'; end
filename = [name ext];
if ~exist(filename,'file')
    error(['File ' filename ' does not exist.']);
end

% Read function from input file
fin = fopen(filename,'r');
while 1        
    fundef = fgetl(fin);
    if ~isemptyline(fundef); break; end
end

% Parse function definition
fundef = regexprep(fundef,'[,()\[\]]',' ');
fundef = regexprep(fundef,' +',' ');    % Trim multiple whitespace

idx = find(fundef == '=');
if ~isempty(idx)
    lhs_list = strread(fundef(1:idx-1),'%s')';
    lhs_list(1) = []; % Remove 'function' token
    rhs_list = strread(fundef(idx+1:end),'%s')';
else
    lhs_list = [];
    rhs_list = strread(fundef,'%s')';
end    

% Store function description
while 1
    desc{1} = fgetl(fin);
    if ~isemptyline(desc{1}); break; end
end
while 1
    desc{end+1} = fgetl(fin);
    if isemptyline(desc{end}) || all(desc{end} ~= '%'); break; end
    idx = find(desc{end} == '%',1);
    desc{end}(1:idx) = [];
end
desc(end) = []; % Discard last line
fclose(fin);    % Close file

nlhs = numel(lhs_list);
funcname = rhs_list{1};
rhs_list(1) = [];
nrhs = numel(rhs_list);

% Parse arguments information from file
[rhssize,rhstype] = parsevariables(desc,'input',nrhs);
[lhssize,lhstype] = parsevariables(desc,'output',nlhs);

% Fill in argument struct
rhs = buildargstruct(rhs_list,rhssize,rhstype,'input');
lhs = buildargstruct(lhs_list,lhssize,lhstype,'output');
allargs = [lhs,rhs];

fileout = [funcname '_mex.c'];
fout = fopen(fileout,'w');
if exist(fileout,'file')
    % error([filename ' already exists. Aborting.']);
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% START WRITING ON FILE

% File header
fprintf(fout, '#include "mex.h"\n#include "math.h"\n#include "matrix.h"\n\n');

% Function definition
fprintf(fout, ['/*\n * ' fileout '\n *\n']);
for i = 1:numel(desc)
    fprintf(fout, ' *%s\n', desc{i});
end
fprintf(fout, [' *\n */\n\n']);

% Macros and definitions
fprintf(fout, '/* Set ARGSCHECK to 0 to skip argument checking (for minor speedup) */\n#define ARGSCHECK 1\n\n');

% Specific function
fprintf(fout, 'void %s( ',funcname);
for i = 1:nlhs
    if i > 1; prefix = ', '; else prefix = ''; end
    fprintf(fout, '%s%s %s%s', prefix, lhs(i).type, repmat('*',[1,lhs(i).pointer]), lhs(i).name);
end
for i = 1:nrhs
    if nlhs > 0 || i > 1; prefix = ', '; else prefix = ''; end
    fprintf(fout, '%s%s %s%s', prefix, rhs(i).type, repmat('*',[1,rhs(i).pointer]), rhs(i).name);
end
fprintf(fout,' )\n{\n\t\n\t/* Write your main calculations here... */\n\t\n}\n\n');

% Main function
fprintf(fout, '/* the gateway function */\n');
fprintf(fout, 'void mexFunction( int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[] )\n{\n');

vartypes = unique({allargs.type});
for i = 1:numel(vartypes)    
    fprintf(fout,'\t%s',vartypes{i});
    first = 1;
    for j = 1:numel(allargs)
        if strcmp(allargs(j).type,vartypes{i});
            pointer = repmat('*',[1,allargs(j).pointer]);
            if first; first = 0; prefix = ' '; else prefix = ', '; end
            fprintf(fout,'%s%s%s',prefix,pointer,allargs(j).name);
        end
    end
    fprintf(fout,';\n');    
end
fprintf(fout,'\n');

% Check for number of arguments (this is always done)
fprintf(fout,'\t/*  check for proper number of arguments */\n\t/* NOTE: You do not need an else statement when using mexErrMsgIdAndTxt\n\t   within an if statement, because it will never get to the else\n\t   statement if mexErrMsgIdAndTxt is executed. (mexErrMsgIdAndTxt breaks\n\t   you out of the MEX-file) */\n');
fprintf(fout,'\tif ( nrhs<%d || nrhs>%d )\n', nrhs, nrhs); 
fprintf(fout,'\t\tmexErrMsgIdAndTxt( "MATLAB:%s:invalidNumInputs",\n\t\t\t"%s inputs required.");\n', funcname, number(nrhs,1));
fprintf(fout,'\tif ( nlhs<%d || nlhs>%d )\n', nlhs, nlhs); 
fprintf(fout,'\t\tmexErrMsgIdAndTxt( "MATLAB:%s:invalidNumOutputs",\n\t\t\t"%s outputs required.");\n\n', funcname, number(nlhs,1));

% Get inputs
for i = 1:nrhs
    argdescription(rhs(i),i,'input',fout);
    if strcmp(rhs(i).sizes{1},'scalar')
        fprintf(fout,'\t%s = (%s) mxGetScalar(prhs[%d]);\n\n', rhs(i).name, rhs(i).fulltype, i-1);
    else
        fprintf(fout,'\t%s = (%s) mxGetPr(prhs[%d]);\n\n', rhs(i).name, rhs(i).fulltype, i-1);
    end
end

% Do input argument checking
fprintf(fout,'\t/* Check sizes of input arguments (define ARGSCHECK to 0 above to skip this part) */\n\tif ( ARGSCHECK ) {\n');
first = 1;
for i = 1:nrhs
    if strcmp(rhs(i).sizes{1},'scalar')
        if first; first = 0; else fprintf(fout,'\n'); end
        fprintf(fout,'\t\tif ( !mxIsDouble(prhs[%d]) || mxIsComplex(prhs[%d]) || (mxGetN(prhs[%d])*mxGetM(prhs[%d])!=1) )\n', i-1, i-1, i-1, i-1);
        fprintf(fout,'\t\t\tmexErrMsgIdAndTxt("MATLAB:%s:%sNotScalar", "Input %s must be a scalar.");\n', funcname, rhs(i).name, upper(rhs(i).name));
    %else
    %    fprintf(fout,'\t%s = (%s) mxGetPr(prhs[%d]);\n\n', rhs(i).name, rhs(i).fulltype, i-1);
    end
end
fprintf(fout,'\t}\n\n');

% Prepare outputs and pointers
for i = 1:nlhs
    argdescription(lhs(i),i,'output',fout);
    n = numel(lhs(i).sizes);
    switch n
        case 1
            fprintf(fout,'\tplhs[%d] = mxCreateDoubleScalar(0.);\n', i-1);            
        case 2
            fprintf(fout,'\tplhs[%d] = mxCreateDoubleMatrix((mwSize) 1, (mwSize) 1, mxREAL);\n', i-1);
        case 3
            for j = 1:n; fprintf(fout, '\tdims_%s[%d] = (mwSignedIndex) (%s);\n', lhs(i).name, j-1, lhs(i).sizes{j}); end
            fprintf(fout,'\tplhs[%d] = mxCreateNumericArray(%d, dims_%s, mxDOUBLE_CLASS, mxREAL);\n', i-1, n, lhs(i).name);
    end
    fprintf(fout,'\t%s = mxGetPr(plhs[%d]);\n\n', lhs(i).name, i-1);
end

% Call subroutine
fprintf(fout, '\t/* Call the C subroutine */\n\t%s(', funcname);
for i = 1:nlhs
    if i > 1; prefix = ', '; else prefix = ''; end
    fprintf(fout, '%s%s', prefix, lhs(i).name);
end
for i = 1:nrhs
    if nlhs > 0 || i > 1; prefix = ', '; else prefix = ''; end
    fprintf(fout, '%s%s', prefix, rhs(i).name);
end
fprintf(fout, ');\n\n');

fprintf(fout,'}\n');
fclose(fout);





end

%--------------------------------------------------------------------------
function tf = isemptyline(line)
%ISEMPTYLINE Return TRUE if line is empty space.
tf = (isnumeric(line) && line == -1) | isempty(regexprep(line,'[\b\f\n\r\t ]',''));
end

%--------------------------------------------------------------------------
function [tf,idx] = issepline(line)
%ISSEPLINE Return TRUE if line is a separator (also return start of sep).
idx = min([Inf,strfind(line,'==='),strfind(line,'%%%')]);
tf = isfinite(idx);
end

%--------------------------------------------------------------------------
function [varsize,vartype] = parsevariables(desc,section,nvars)
%PARSEVARIABLES Parse argument description for size and type.

varsize = [];
vartype = [];

% Parse variables
found = 0;
for i = 1:numel(desc)
    line = desc{i};
    if ~issepline(line); continue; end
    idx = min([Inf,strfind(lower(line),section)]);
    if isfinite(idx); found = 1; break; end    
end

ivars = 0;
if found
    for i = i+1:numel(desc)
        line = desc{i};
        if issepline(line); break; end
        line = regexprep(line,'[%]',' ');
        if isemptyline(line); break; end
        
        ivars = ivars + 1;
        if ivars > nvars
            error(['Too many ' section ' arguments in file description. Each argument should have one line.']);
        end
        
        % Find sizes, last square brackets
        idx1 = find(line == '[',1,'last')+1;
        idx2 = idx1 - 1 + find(line(idx1+1:end) == ']',1);     
        if isempty(idx1) || isempty(idx2)
            error(['Cannot find size information for ' section ' #' num2str(ivars) ' in ' filein '.']);
        end        
        varsize{ivars} = line(idx1:idx2);
        
        % Find type, last round brackets
        idx1 = find(line == '(',1,'last')+1;
        idx2 = idx1 - 1 + find(line(idx1+1:end) == ')',1);        
        if isempty(idx1) || isempty(idx2)
            error(['Cannot find type information for ' section ' #' num2str(ivars) ' in ' filein '.']);
        end        
        vartype{ivars} = line(idx1:idx2);
        
    end
end

if ivars < nvars
    error('Too few input arguments in file description. Each argument should have one line.');
end

end

%--------------------------------------------------------------------------
function astruct = buildargstruct(alist,asize,atype,section)

n = numel(alist);
for i = 1:n
    % Remove whitespace from name (if any)
    astruct(i).name = regexprep(alist{i},'[\b\f\n\r\t ]',' ');
    
    % Scan argument sizes
    temp = regexprep(asize{i},'[\b\f\n\r\t\[\],; ]',' ');
    errstr = ['Cannot parse ' section ' argument #' num2str(i) ' size in function description.'];
    if isempty(temp); error(errstr); end
    sizes = strread(temp,'%s')';
    if isempty(sizes); error(errstr); end
    
    if numel(sizes) == 1
        if any(strcmpi(sizes{1},{'1','scalar'}))
            astruct(i).sizes{1} = 'scalar';
        else
            error([upper(section(1)) section(2:end) ' argument #' num2str(i) ' size has only one dimension. Write ''1'' or ''scalar'' for a scalar value.']);
        end
    else
        if all(strcmp(sizes,'1'))
            astruct(i).sizes{1} = 'scalar';
        else            
            astruct(i).sizes = sizes;
        end
    end
    
    % Scan argument type
    temp = atype{i};
    errstr = ['Cannot parse ' section ' argument #' num2str(i) ' type in function description.'];
    if isempty(temp); error(errstr); end
    
    % Check if it is a pointer
    astruct(i).pointer = max(sum(temp == '*'), numel(astruct(i).sizes) > 1);

    if astruct(i).pointer && strcmp(astruct(i).sizes{1},'scalar')
        error([upper(section(1)) section(2:end) ' argument #' num2str(i) ' is a scalar pointer. Just declare it as a scalar.']);
    end
    
    temp = regexprep(temp,'[\b\f\n\r\t\[\],;* ]','');
    
    switch lower(temp)
        case {'int','integer'}; astruct(i).type = 'int';
        case 'double'; astruct(i).type = 'double';
        case 'float'; astruct(i).type = 'float';
        case {'size','mwsize'}; astruct(i).type = 'mwSize';
        case {'index','signedindex','mwsignedindex'}; astruct(i).type = 'mwSignedIndex';
        otherwise
            warnstr = ['Unknown variable type ''' temp ''' for ' section ' argument #' num2str(i) ' in function description.'];
            warning(warnstr);
            astruct(i).type = temp;
    end
    
    if astruct(i).pointer && ~strcmp(astruct(i).type,'double')
        warning([upper(section(1)) section(2:end) ' argument #' num2str(i) ' is a non-double pointer. This might cause problems.']);
    end
    astruct(i).fulltype = [astruct(i).type repmat('*',[1,astruct(i).pointer])];
    
end

end
%--------------------------------------------------------------------------
function argdescription(arg,n,section,fout)
%ARGDESCRIPTION Write argument description

ordinal = {'1st','2nd','3rd','4th','5th','6th','7th','8th','9th','10th', ...
    '11th','12th','13th','14th','15th','16th','17th','18th','19th','20th'};

switch lower(section)
    case 'input'
        fprintf(fout,'\t/* Get %s input (', ordinal{n});
    case 'output'
        fprintf(fout,'\t/* Pointer to %s output (', ordinal{n});
end
fprintf(fout,'%s, ', upper(arg.name));

for j = 1:numel(arg.sizes)
    if j > 1; prefix = '-by-'; else prefix = ''; end
    fprintf(fout,'%s%s',prefix,arg.sizes{j});
end
fprintf(fout,' %s) */\n', arg.type);

end

%--------------------------------------------------------------------------
function s = number(n,firstupper)
%NUMBER Return a string with an number
if nargin < 2 || isempty(firstupper); firstupper = 0; end

switch n
    case 0; s = 'zero';
    case 1; s = 'one';
    case 2; s = 'two';
    case 3; s = 'three';
    case 4; s = 'four';
    case 5; s = 'five';
    case 6; s = 'six';
    case 7; s = 'seven';
    case 8; s = 'eight';
    case 9; s = 'nine';
    case 10; s = 'ten';
    otherwise; s = num2str(n);
end
if firstupper; s(1) = upper(s(1)); end

end
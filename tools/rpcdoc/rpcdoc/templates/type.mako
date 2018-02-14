<%inherit file="base.mako"/>
<%namespace name="partials" file="partials.mako"/>

% if t.is_struct:
    ${partials.struct(t)}
% elif t.is_typedef:
    ${partials.typedef(t)}
%endif
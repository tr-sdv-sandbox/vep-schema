{# VEP-Schema Protobuf Template #}
{# Fixed version addressing: #}
{#   - int8/int16 → sint32 mapping #}
{#   - uint8/uint16 → uint32 mapping #}
{#   - Preserve explicit enum values #}
{# #}
{# Based on COVESA IFEX AST_protobuf.tpl #}
{# (C) 2022 Robert Bosch GmbH, (C) 2025 VEP Contributors #}
// Generated from {{ item.name }}.ifex by vep-schema
// DO NOT EDIT - regenerate with: ./tools/run.sh generate-proto
syntax = "proto3";

{# Type mappings: IFEX → Protobuf #}
{# Protobuf only has: int32, int64, uint32, uint64, sint32, sint64, bool, float, double, string, bytes #}
{% set typedefs = dict() %}
{# Signed integers: use sint32/sint64 for efficient encoding of negative values #}
{% set x=typedefs.__setitem__("int8", "sint32") %}
{% set x=typedefs.__setitem__("int16", "sint32") %}
{% set x=typedefs.__setitem__("int32", "sint32") %}
{% set x=typedefs.__setitem__("int64", "sint64") %}
{# Unsigned integers: uint8/uint16 widen to uint32 #}
{% set x=typedefs.__setitem__("uint8", "uint32") %}
{% set x=typedefs.__setitem__("uint16", "uint32") %}
{# boolean → bool #}
{% set x=typedefs.__setitem__("boolean", "bool") %}

{# Macro to convert IFEX types to protobuf, handling arrays #}
{% macro convert_type(datatype) -%}
  {%- set is_array = datatype.endswith('[]') -%}
  {%- if is_array -%}
    {%- set base = datatype[:-2] -%}
  {%- else -%}
    {%- set base = datatype -%}
  {%- endif -%}
  {%- if base in typedefs -%}
    {%- set mapped = typedefs[base] -%}
  {%- else -%}
    {%- set mapped = base|replace(".", "_") -%}
  {%- endif -%}
  {%- if is_array -%}
repeated {{ mapped }}
  {%- else -%}
{{ mapped }}
  {%- endif -%}
{%- endmacro %}

package vep.{{ item.name }};

{% for n in item.namespaces %}
// Namespace: {{ n.name }}
{% if n.description %}// {{ n.description }}{% endif %}

{# Process typedefs first to build type mapping table #}
{% for t in n.typedefs %}
{# Add typedef to our mapping table #}
{% if t.datatype in typedefs %}
  {% set type = typedefs[t.datatype] %}
{% else %}
  {% set type = t.datatype %}
{% endif %}
{% set x=typedefs.__setitem__(t.name, type) %}
{% endfor %}

{# Generate enums with explicit values preserved #}
{% for e in n.enumerations %}
// {{ e.description|default("Enumeration " + e.name, true) }}
enum {{ e.name }} {
{% for opt in e.options %}
  {{ opt.name }} = {{ opt.value }};
{% endfor %}
}

{% endfor %}
{# Generate structs as messages #}
{% for s in n.structs %}
// {{ s.description|default("Struct " + s.name, true) }}
message {{ s.name }} {
{% for m in s.members %}
  {{ convert_type(m.datatype) }} {{ m.name }} = {{ loop.index }};
{% endfor %}
}

{% endfor %}
{# Generate methods as request/response messages + service #}
{% for method in n.methods %}
// Method: {{ method.name }}
{% if method.description %}// {{ method.description }}{% endif %}

message {{ method.name }}_request {
{% for arg in method.input %}
  {{ convert_type(arg.datatype) }} {{ arg.name }} = {{ loop.index }};
{% endfor %}
}

message {{ method.name }}_response {
{% for arg in method.output %}
  {{ convert_type(arg.datatype) }} {{ arg.name }} = {{ loop.index }};
{% endfor %}
}

service {{ method.name }}_service {
  rpc {{ method.name }}({{ method.name }}_request) returns ({{ method.name }}_response);
}

{% endfor %}
{# Generate events as messages #}
{% for event in n.events %}
// Event: {{ event.name }}
{% if event.description %}// {{ event.description }}{% endif %}

message {{ event.name }} {
{% for arg in event.input %}
  {{ convert_type(arg.datatype) }} {{ arg.name }} = {{ loop.index }};
{% endfor %}
}

{% endfor %}
{# Generate properties as value messages + service #}
{% for prop in n.properties %}
// Property: {{ prop.name }}
{% if prop.description %}// {{ prop.description }}{% endif %}

message {{ prop.name }}_value {
  {{ convert_type(prop.datatype) }} value = 1;
}

message {{ prop.name }}_request {}

service {{ prop.name }}_service {
  rpc get_{{ prop.name }}({{ prop.name }}_request) returns ({{ prop.name }}_value);
  rpc set_{{ prop.name }}({{ prop.name }}_value) returns ({{ prop.name }}_value);
}

{% endfor %}
{% endfor %}

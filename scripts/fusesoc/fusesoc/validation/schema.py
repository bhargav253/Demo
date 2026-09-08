# SPDX-License-Identifier: Apache-2.0
"""Version 1 core validation schema; deliberately independent of HDL filesets."""

def obj(properties, required=()):
    return dict(type='object', properties=properties, required=list(required), additionalProperties=False)


def names(value):
    return dict(type='object', patternProperties={'^[A-Za-z][A-Za-z0-9_.-]*$': value}, additionalProperties=False, minProperties=1)


string = {'type':'string', 'minLength':1}
strings = {'type':'array', 'items':string, 'minItems':1, 'uniqueItems':True}
positive = {'type':'integer', 'minimum':1}
params = {'type':'object', 'propertyNames':{'pattern':'^[A-Za-z][A-Za-z0-9_]*$'},
          'additionalProperties':{'type':['string','integer','boolean']}}
seeds = {'type':'array', 'items':{'type':'integer','minimum':0,'maximum':4294967295}, 'minItems':1, 'uniqueItems':True}
BUILD = obj({'target':string, 'kind':{'enum':['simulation','target']}, 'parameters':params,
             'pass_pattern':string, 'fail_pattern':string, 'wave_arg':string,
             'coverage_arg':string, 'timeout':positive}, ['target','kind'])
TEST = obj({'build_mode':string, 'parameters':params, 'manifest':string, 'timeout':positive,
            'description':string}, ['build_mode'])
ENTRY = obj({'tests':strings, 'run_modes':strings, 'seeds':seeds}, ['tests'])
SCHEMA = obj({'version':{'const':1}, 'description':string,
              'build_modes':names(BUILD), 'run_modes':names(obj({'parameters':params})),
              'tests':names(TEST), 'regressions':names({'type':'array','items':ENTRY,'minItems':1}),
              'coverage_build_mode':string, 'limitations':strings},
             ['version','build_modes','run_modes','tests','regressions','limitations'])
POLICY = obj({'version':{'const':1}, 'jobs':positive, 'timeout':positive,
              'max_log_mib':positive, 'max_wave_mib':positive, 'max_build_file_mib':positive},
             ['version','jobs','timeout','max_log_mib','max_wave_mib','max_build_file_mib'])

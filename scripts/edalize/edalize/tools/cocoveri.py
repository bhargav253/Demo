# Copyright edalize contributors
# Licensed under the 2-Clause BSD License, see LICENSE for details.
# SPDX-License-Identifier: BSD-2-Clause

from io import StringIO
import os
import logging
from pathlib import Path

from edalize.tools.edatool import Edatool
from edalize.utils import EdaCommands

logger = logging.getLogger(__name__)

class Cocoveri(Edatool):

    _description = "CoCoVeri Makefile"

    TOOL_OPTIONS = {}

    @classmethod
    def get_tool_options(cls):
        return cls.TOOL_OPTIONS
    

    def setup(self, edam):
        super().setup(edam)
        src_file = StringIO()
        
        for f in self.files:
            if f['file_type'] == 'verilogSource':
                fname = f['name']
                src_file.write(f"{fname}\n")

        output_file = self.name + ".src"

        self.commands = EdaCommands()
        commands = EdaCommands()

        commands.set_default_target(output_file)
        self.commands = commands
        self.src_file = src_file

        self.config_file = self.name + '.src'
        
        print("HUHUH can i do this in the setup")        

        template_vars = {
            "name": self.name,
            "toplevel": self.toplevel,
        }

        self.render_template("Makefile.j2", "Makefile", template_vars)

        with open(os.path.join(self.work_root, self.config_file,), "w") as cfg_file:
            cfg_file.write(self.src_file.getvalue())

        print("done here")                    
        
    def run_main(self):
        print("in run_main")
        self._run_tool("make")

    def run(self):
        print("in run")        
        args = ["run"]
        return ("make", args, self.work_root)
        


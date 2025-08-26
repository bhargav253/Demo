from edalize.flows.edaflow import Edaflow

class Cocoveri(Edaflow):

    argtypes = ["plusarg", "vlogdefine", "vlogparam"]

    FLOW_DEFINED_TOOL_OPTIONS = {
        "secondcustomtool": {"some_option": "some_value", "other_option": []},
    }

    @classmethod
    def get_tool_options(cls, flow_options):
      # Add any frontends used in this flow
      flow = flow_options.get("frontends", []).copy()

      # Add the main tool flow
      flow.append("firstcustomtool")
      flow.append("secondcustomtool")
      return cls.get_filtered_tool_options(flow, cls.FLOW_DEFINED_TOOL_OPTIONS)

    def configure(self):
        print("Configuring custom flow")

    def build(self):
        print("Building with custom flow")

    def run(self, args):
        print("Running custom flow")

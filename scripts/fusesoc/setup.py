from setuptools import setup, find_packages

setup(
    name="fusesoc",
    version="2.4.4",
    packages=find_packages(),
    include_package_data=True,
    install_requires=[
        # dependencies from requirements.txt
    ],
    entry_points={
        'console_scripts': [
            'fusesoc=fusesoc.main:main',
        ],
    },
)

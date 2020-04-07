import sys, glob
import ruamel
from jobs.utils.namer import editor_filepath, packages_filepath, project_filepath_specific,project_filepath_all
from jobs.projects.project_standalone import Project_StandaloneJob
from jobs.projects.project_standalone_build import Project_StandaloneBuildJob
from jobs.projects.project_not_standalone import Project_NotStandaloneJob
from jobs.projects.project_all import Project_AllJob
from jobs.editor.editor import Editor_PrimingJob

# TODO:
# - variables to store path names (change only once)
# - functions to generate job ids (and names)
# - see if less duplication possible among the jobs
# - squash reused cmd like npm install, artifacts links etc

def load_yml(filepath):
    with open(filepath) as f:
        return yaml.load(f)

def dump_yml(filepath, yml_dict):
    with open(filepath, 'w') as f:
        yaml.dump(yml_dict, f)

def create_project_specific_jobs(project_metafile):

    metafile = load_yml(project_metafile)
    project = metafile["project"]

    for platform in metafile['platforms']:
        for api in platform['apis']:

            yml = {}
            for editor in metafile['editors']:
                for test_platform in metafile['test_platforms']:

                    if test_platform["name"].lower() == 'standalone':
                        job = Project_StandaloneJob(project, editor, platform, api, test_platform)
                        yml[job.job_id] = job.yml
                        
                        if platform["standalone_split"]:
                            job = Project_StandaloneBuildJob(project, editor, platform, api)
                            yml[job.job_id] = job.yml
                    else:
                        job = Project_NotStandaloneJob(project, editor, platform, api, test_platform)
                        yml[job.job_id] = job.yml
                    
            # store yml per [project]-[platform]-[api]
            yml_file = project_filepath_specific(project["name"], platform["name"], api["name"])
            dump_yml(yml_file, yml)



def create_project_all_jobs(project_metafile):

    metafile = load_yml(project_metafile)

    yml = {}
    for editor in metafile['editors']:
        job = Project_AllJob(metafile["project"]["name"], editor, metafile["all"]["dependencies"])
        yml[job.job_id] = job.yml

    yml_file = project_filepath_all(metafile["project"]["name"])
    dump_yml(yml_file, yml)



def create_editor_job(editor_metafile):

    metafile = load_yml(editor_metafile)

    yml = {}
    for platform in metafile["platforms"]:
        for editor in metafile["editors"]:
            job = Editor_PrimingJob(platform, editor, metafile["agent"])
            yml[job.job_id] = job.yml

    dump_yml(editor_filepath(), yml)



# TODO clean up the code, make filenames more readable/reuse, split things appropriately (eg editor, files, etc), fix scrip arguments, fix testplatforms (xr), ...
if __name__== "__main__":

    # configure yaml
    yaml = ruamel.yaml.YAML()
    yaml.width = 4096
    yaml.indent(offset=2, mapping=4, sequence=5)


    # create editor
    create_editor_job('config/z_editor.metafile')


    # create yml jobs for each specified project (universal, shadergraph, vfx_lwrp, ...)
    args = sys.argv
    projects = glob.glob('config/[!z_]*.metafile') if 'all' in args else [f'config/{project}.metafile' for project in args[1:]]   
    print(f'Running: {projects}')

    for project_metafile in projects:
        create_project_specific_jobs(project_metafile) # create jobs for testplatforms
        create_project_all_jobs(project_metafile) # create All_ job




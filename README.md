# Azure Machine Learning Automation

## Automation PowerShell script example for automating Azure Machine Learning experiments.

### This repository contains a sample PowerShell script made by utilizing Azure Machine Learning PowerShell module.

_Link to module : https://github.com/hning86/azuremlps_

### This walk-through is based on a Machine learning experiment in Azure Machine Learning Workspace as follows: 

1. The experiment already exists in an existing Azure Machine Learning workspace.
2. The experiment has the necessary data sets and machine learning models in the workspace.
3. The experiment also has input and output nodes which fetch and push data into SQL server database respectively.
4. It is required to deploy this experiment to another resource group having a different Azure Machine Learning workspace in the same or different Azure subscription (provided the Azure service principal has access to both Azure subscriptions).

### With the use of the sample script one can achieve the following

1. Deploy existing Azure Machine Learning experiments from one workspace to another.
2. Import data sets and models alongwith the experiment metadata.
3. As the SQL nodes in the experiment need to be authenticated, the same cannot be automated but is implemented through a 5 minutes time-out halt of the script so that the user can go to AML workspace, authenticate the nodes and once the same is done, the script will resume execution.
4. Run the experiment to test if everything works.
5. On successful execution publish the experiment as a web service for client applications to consume the same.

## Pre-Configuration:

### The following steps are required to configure the necessary files before executing the deployment script:

1. Install the **Azure ML PowerShell module** from the link in the description.
2. Open the **config.json**: This file will be used as a context provider for the script to execute the steps with respect to the Azure Machine Learning workspace configured by the same.

* Replace the value of **Location** variable with the location of the Azure Machine Learning workspace.
* Replace the value of **WorkspaceId** variable with the workspace Id copied from Azure Machine Learning Workspace portal.
* Replace the value of **AuthorizationTokenvariable** with the Authorization Token copied from Azure Machine Learning Workspace portal.

3. Open the **AMLExperiments.json**: This file will provide the list of experiments that are to be copied from the source workspace to the target workspace. In case of one experiment, it will have only one entry in the **AMLExperiments** array object.
* Replace the value of **EXP_name** variable with the name of the Azure Machine Learning Experiment name.
* Add as many objects with **EXP_name** initialized as the number of experiments in the workspace.
* Leave out the **LS_name** field as default for now. It will be dealt with during ADF Automation Walkthrough as it would include consuming the published web service for the given experiment to be consumed by an ADF linked service.

4. Open the **ADF.Parameters_Dev.json**: This file contains configuration values required for the SQL server as well as **amlConfiguration** object which is an array of objects having various properties pertaining to an AML Experiment and its published web service.

* Add as many objects to the **amlConfiguration** array as initialized in **AMLExperiments** array of **AMLExperiments.json** (same as the number of experiments in the workspace).
* Initialize the **amlName** variable with the name of the Azure Machine Learning Experiment name.
* Ensure all other property values are empty like **value** property in **amlEndPoint** & **amlApiKey** object. These will be populated with the web service endpoint and api key respectively on executing the AML script. The same will be used to populate AML linked service template for the given experiment for ADF pipelines to consume the same. The same will be discussed in ADF automation walkthrough.
* Ensure the properties **datahubSqlServerName**, **datahubDatabaseName** & **datahubSqlServerAdminLogin** are populated with the values for SQL server name, SQL server database name & SQL server database admin login Id respectively.


### Once the pre-configuration steps are complete, the AMLExperimentDeployment.ps1 can be invoked with the following arguments:

* executionPath = Execution directory path of the script (physical location path of the script) ex: C:\AML
* mlwName = Source AML workspace name
* mlwTargetName = Target AML workspace name
* env = environment identifier for template file path ex: dev
* templateFilePath = ADF Template file path address ex: C:\AML\Templates\
* mlwSubscriptionId = source subscription id
* targetmlwSubscriptionId = target subscription id
* ClientId = client id of azure spn
* resourceAppIdURI = app id uri of azure spn
* TenantId = tenant id of azure ad
* ClientKey = client secret of azure spn

### The script performs the following steps:
 
1. Parses the adf template parameters file by combining the **templatefilepath** and **env** variables and gets the values for SQL server name, SQL server database name & SQL server admin user name.
2. Parses the AMLExperiments file by combining **templatefilepath** with **"AMLExperiments.json"** & gets the names of AML experiments configured to be deployed.
4. For every experiment discovered from **AMLExperiments.json** file, the following steps are performed:

* Set azure context to target azure subscription & AML context to target AML workspace by dynamically obtaining AML config values of the target workspace and updating the **config.json** and check if the experiment already exist there with **state** as **finished**, if so: skip the experiment in the loop else continue execution.
* Set azure context to source azure subscription & AML context to source AML workspace by dynamically obtaining AML config values of the source workspace and updating the **config.json** Get & get the reference to the experiment from the source workspace.
* **Copy** the experiment from source to target workspace (this will ensure the data set, models and metadata is copied).
* Set azure context to target azure subscription & AML context to target AML workspace by dynamically obtaining AML config values of the target workspace and updating the **config.json** & get reference to the experiment from the target workspace.
* Export the experiment to a file and save it in **ExportedExperimentGraphs** folder by forming the full file path for the same by using the **executionPath** & **target experiment description**.
* The experiment is exported as a json file. The script will modify the json file so that all SQL nodes in the experiment point to the new SQL server (target SQL server details obtained from **ADFparameters.json** file previously).
* The copied experiment is removed from target workspace and a new experiment is created with same name as that of the source workspace experiment but imported with updated json.
* This will ensure that the experiment points to new SQL server configuration instead of the one defined in the source workspace experiment.
* Now a timeout of **5 minutes** is set which polls for authentication status of all SQL nodes in the experiment. If the user enters the password and authorizes the connection to each node in the target workspace experiments within 5 minutes then the script will continue execution else it will break out of the timeout logic and skip to next experiment in the outermost loop. _(Tip: In order to identify the SQL node, the script matches the Comment property of the node to a predefined comment which should match with that of the SQL node in source workspace experiment & should be the case for all SQL nodes)_.
* Once all nodes are authroized the execution will break out of the 5 minute stop watch loop for polling authorization status and start the experiment run.
* If the expirement run fails, the script will throw an error else execution will proceed further.
* Finally the **GetWebServiceDetails** function will be called and the experiment name will be passed to the same via the **expName** parameter.
* This function will publish the experiment in the target worksapce as a **web service** and fetch the **web service end point as well as the API key** and update the 2 values in the **ADF.Parameters.json** file against the object in **amlConfiguration** corresponding to the experiment in the target workspace by searching through the **name** property of the experiment and matching it with **amlName** property. This is the reason why each experiment name was entered in the **amlConfiguration** object during the **pre-configuration** steps.
* Finally the file is saved and all steps are repeated for each experiment name in the **expNames** array.

On successful execution of the script, the experiments will be copied from source workspace to target workspace with data sets, models and metadata, along with updated SQL server endpoints in the SQL server nodes (authorized by manual intervention of typing the password in the password field for SQL server authorization for each such node), doing a test run for the experiment, publishing as a web service and saving the web service end point and API key to the **ADFParameters.json** config file so that the same can now be used to dynamically create linked service against the AML experiment for ADF to consume the same and call the AML experiment in the target workspace.


Here is a **clean, production‑quality AI‑agent prompt** you can paste directly into your Copilot / LLM environment.

It is written to:

*   build and test a deletion solution for an Azure DevOps *service connection* via the REST API
*   run on **Windows or Linux**
*   use **PowerShell** as the preferred automation engine
*   require a complete, testable workflow
*   operate safely with PAT authentication

***

## **AI Agent Prompt (Final Version)**

**Goal:**  
Design, build, and fully test a complete working solution that deletes an Azure DevOps Service Connection using the Azure DevOps REST API. The solution must work on **Windows or Linux**, with **PowerShell** as the primary language. The workflow must support PAT‑based authentication and handle project‑scoped service connections. The solution must validate inputs, execute the DELETE call, return success/failure status, and optionally verify the deletion.

**Context:**

*   Azure DevOps service connections are project‑scoped resources.
*   Deletion requires:
    *   organization name
    *   project name
    *   service connection (endpoint) ID
    *   PAT with scope: “Service Connections (Read, Query, Manage)”
*   The REST URL format is:  
    `https://dev.azure.com/{ORG}/{PROJECT}/_apis/serviceendpoint/endpoints/{ENDPOINT_ID}?api-version=7.1-preview.4`
*   Authentication uses **Basic** header with this exact encoding:  
    Base64( ":" + PAT )  
    (username is an empty string)

**Requirements for the agent:**

1.  Produce clean PowerShell code that works on both Windows PowerShell 5.1 and PowerShell 7+ on Linux.
2.  Include full parameterization:
    *   org
    *   project
    *   endpointId
    *   pat
3.  Build a function `Remove-AdoServiceConnection` that:
    *   validates parameter formats
    *   constructs the Base64 PAT header correctly
    *   performs the DELETE via Invoke‑WebRequest or Invoke‑RestMethod
    *   handles exceptions and prints actionable errors
4.  Produce a self‑test routine that:
    *   sends a GET request before deletion
    *   calls the delete function
    *   sends a GET request after deletion
    *   reports PASS / FAIL
5.  Output must be a **single complete script** ready to save as `remove-sc.ps1` and run cross‑platform.
6.  Do **not** require Azure CLI login; rely only on the PAT.
7.  Include clear instructions for running the script on Windows and Linux.
8.  Do not include placeholders—return fully working code using variables.

**Deliverables:**

*   One complete PowerShell script
*   Clear setup steps
*   Example command to execute the script
*   Troubleshooting checks for:
    *   PAT permission issues
    *   wrong endpoint ID
    *   incorrect project path
    *   service connection in corrupted state

***

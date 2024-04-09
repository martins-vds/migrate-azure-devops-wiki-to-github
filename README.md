# Migrate Azure DevOps Wiki to GitHub

This repository contains a PowerShell script, `ConvertTo-GithubWiki.ps1`, that can be used to migrate an Azure DevOps Wiki to GitHub.

## Prerequisites

Before running the script, make sure you have the following:

- PowerShell installed on your machine.
- Azure DevOps Wiki that you want to migrate.
- A GitHub repository where you want to migrate the wiki.

## Usage

1. Clone this repository to your local machine.
2. Get the Azure DevOps Wiki repository URL.
3. Get the GitHub repository URL where you want to migrate the wiki.
4. Open a PowerShell terminal as an administrator.
5. Navigate to the cloned repository.
6. Run the following command:

    ```powershell
    .\ConvertTo-GithubWiki.ps1 -AzureDevOpsWikiRepositoryUrl "<Azure DevOps Wiki Repository URL>" -GitHubRepositoryUrl "<GitHub Repository URL>"
    ```

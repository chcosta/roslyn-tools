## Description

Toolset-Boostrap is the method used to quickly acquire a version of the RepoToolset.


## Scenarios

Toolset-bootstrap is useful for a few different scenarios involving the repo-toolset.

- You can use the bootstrapping to download a version of the repo-toolset scaffolding and commit it to your repo.  This will provide a quick way to onboard new repos. simply run the obtain script, and check in the extracted files then create your root `ToolsetVersions.props` / `Directory.Build.props` / `Directory.Build.targets` files as you normally would.


- You can use this method to download the latest version of the Repo-Toolset scaffolding and update what your repo is using.  Another use, is to simplify onboarding a repo to use the RepoToolset functionality, 

- You can use the bootstrapping mechanism to quickly download a version of the toolset, add a toolset package, and make use of that package functionality.  This method would be more relevant for non-repo specific functionality.

## Obtaining the toolset

Executing https://github.com/chcosta/roslyn-tools/blob/bootstrap/build/bootstrap/obtain/toolset-install.ps1 will download the latest Repo-Toolset zip file and extract its contents into the `.\build` directory.

Example:
```
> @powershell -NoProfile -ExecutionPolicy unrestricted -Command "&([scriptblock]::Create((Invoke-WebRequest -useb 'https://raw.githubusercontent.com/chcosta/roslyn-tools/bootstrap/build/bootstrap/obtain/toolset-install.ps1')))
```

The Toolset-Bootstrap files which come with this package are enough to install a version of the repo-toolset and dotnet CLI.  Restore and AddPackageToToolset functionality requires knowing what versions of the CLI / toolset you are targeting.  You can define which versions of the toolset / CLI are installed by either providing them on the command-line, or defining a `ToolsetVersions.props` file.  Other utility scripts (Build.cmd, Test.cmd, CIBuild.cmd, etc...) do not perform restore operations and do not require toolset versions knowledge # TODO: confirm this is true / or make this true.

### Defining ToolsetVersions.props 
For the general case of using the repo-toolset, **it is recommended**, that you provide a `ToolsetVersions.props` file which is commited to the repo in any parent directory of `build`.  The `ToosetVersions.props` file defines the versions of the RepoToolset and CLI which are installed.  TODO: We can provide an overridable version of this file so that this is not a strict requirement for bootstrapping.  

Sample `ToolsetVersions.props` file:

``` MSBuild
<?xml version="1.0" encoding="utf-8"?>
<Project ToolsVersion="4.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <RoslynToolsRepoToolsetVersion>1.0.0-beta-62506-01</RoslynToolsRepoToolsetVersion>
    <DotNetCliVersion>2.0.2</DotNetCliVersion>
  </PropertyGroup>
</Project>
```

### Specifying toolset versions on the command-line

The Toolset-Bootstrap archive for repo-toolset provides a number of utility scripts.  An alternative to committing a `ToolsetVersion.props` file is to excplitly specify toolset versions on the command-line.  You can explicitly specify versions of the Repo-Toolset or DotNet CLI on the command-line by passing the `-toolsetversion <value>` and `-dotnetcliversion <value>` arguments.

Example:
```
> Restore.cmd -toolsetversion 1.0.0-beta-62506-01 -dotnetcliversion 2.0.2
```

#### What is the scenario where providing explicit versions is preferred over the checked-in ToolsetVersions.props model?

As a quick and easy method to gain access to toolset packages and utilize functionality, you may not want to commit toolset version information to a repo, or you may not have a specify repo to commit `ToolsetVersion.props` files too.

An example would be a VSTS build definition which is used for publishing a repo, but the version of a package which the publishing utilizes is tied to the repo it is running, and not the publishing piece itself.  In this case, many different VSTS repo's could use the same publishing repo, but tell it what package version to use rather than having to commit information for each version which the definition services.  The publishing repo could perform these steps...

Example:
```
> @powershell -NoProfile -ExecutionPolicy unrestricted -Command "&([scriptblock]::Create((Invoke-WebRequest -useb 'https://raw.githubusercontent.com/chcosta/roslyn-tools/bootstrap/build/bootstrap/obtain/toolset-install.ps1')))
> build\AddPackageToToolset.cmd -packagename Microsoft.DotNet.Build.Tasks.Feed -packageversion 2.1.0-prerelease-02411-04 -packagesource https://dotnet.myget.org/F/dotnet-buildtools/api/v3/index.json -toolsetversion 1.0.0-beta-62512-02 -dotnetcliversion 2.0.2
> msbuild build\Toolset.csproj /t:PublishPackagesToBlobFeed ...
```

In this example, we obtain the toolset, then we run a command which adds a PackageReference to the Toolset for the package that contains the functionality we want to use.  The next step is to use MSBuild to build our Toolset project and use the target we acquired from the additional package.  Note that the "PublishPackagesToBlobFeed" functionality is not part of the Repo-Toolset, but we enabled that functionality with the "AddPackageToToolset" script.




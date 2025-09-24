import { Octokit } from '@octokit/rest'
import { readFileSync, readdirSync, statSync } from 'fs'
import { join, relative } from 'path'

let connectionSettings;

async function getAccessToken() {
  if (connectionSettings && connectionSettings.settings.expires_at && new Date(connectionSettings.settings.expires_at).getTime() > Date.now()) {
    return connectionSettings.settings.access_token;
  }
  
  const hostname = process.env.REPLIT_CONNECTORS_HOSTNAME
  const xReplitToken = process.env.REPL_IDENTITY 
    ? 'repl ' + process.env.REPL_IDENTITY 
    : process.env.WEB_REPL_RENEWAL 
    ? 'depl ' + process.env.WEB_REPL_RENEWAL 
    : null;

  if (!xReplitToken) {
    throw new Error('X_REPLIT_TOKEN not found for repl/depl');
  }

  connectionSettings = await fetch(
    'https://' + hostname + '/api/v2/connection?include_secrets=true&connector_names=github',
    {
      headers: {
        'Accept': 'application/json',
        'X_REPLIT_TOKEN': xReplitToken
      }
    }
  ).then(res => res.json()).then(data => data.items?.[0]);

  const accessToken = connectionSettings?.settings?.access_token || connectionSettings.settings?.oauth?.credentials?.access_token;

  if (!connectionSettings || !accessToken) {
    throw new Error('GitHub not connected');
  }
  return accessToken;
}

async function getUncachableGitHubClient() {
  const accessToken = await getAccessToken();
  return new Octokit({ auth: accessToken });
}

function getAllFiles(dirPath, arrayOfFiles = []) {
  const files = readdirSync(dirPath)

  files.forEach(file => {
    const fullPath = join(dirPath, file)
    if (statSync(fullPath).isDirectory()) {
      if (!file.startsWith('.') && file !== 'node_modules' && file !== 'downloads') {
        arrayOfFiles = getAllFiles(fullPath, arrayOfFiles)
      }
    } else {
      if (!file.startsWith('.') && !file.endsWith('.log')) {
        arrayOfFiles.push(fullPath)
      }
    }
  })

  return arrayOfFiles
}

async function syncToGitHub() {
  try {
    console.log('🔑 Getting GitHub client...')
    const octokit = await getUncachableGitHubClient()
    
    const owner = 'Saucyfinn'
    const repo = 'mypropertyview'
    const branch = 'main'
    
    console.log('📁 Getting repository info...')
    const { data: repoData } = await octokit.rest.repos.get({ owner, repo })
    
    console.log('🌳 Getting latest commit...')
    const { data: branchData } = await octokit.rest.repos.getBranch({ owner, repo, branch })
    const latestCommitSha = branchData.commit.sha
    
    console.log('📂 Collecting local files...')
    const files = getAllFiles('.')
    
    const tree = []
    for (const filePath of files) {
      const content = readFileSync(filePath, 'utf8')
      const path = relative('.', filePath).replace(/\\/g, '/')
      
      tree.push({
        path,
        mode: '100644',
        type: 'blob',
        content
      })
    }
    
    console.log(`📝 Creating tree with ${tree.length} files...`)
    const { data: treeData } = await octokit.rest.git.createTree({
      owner,
      repo,
      tree,
      base_tree: latestCommitSha
    })
    
    console.log('💾 Creating commit...')
    const { data: commitData } = await octokit.rest.git.createCommit({
      owner,
      repo,
      message: `Sync from Replit - Updated cross-platform property app with removed address confirmation and AR button confirmation`,
      tree: treeData.sha,
      parents: [latestCommitSha]
    })
    
    console.log('🚀 Updating branch...')
    await octokit.rest.git.updateRef({
      owner,
      repo,
      ref: `heads/${branch}`,
      sha: commitData.sha
    })
    
    console.log('✅ Successfully synced to GitHub!')
    console.log(`🔗 Commit: https://github.com/${owner}/${repo}/commit/${commitData.sha}`)
    
  } catch (error) {
    console.error('❌ Error syncing to GitHub:', error.message)
    throw error
  }
}

syncToGitHub()
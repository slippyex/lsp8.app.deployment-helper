import * as fs from 'fs-extra';
import * as glob from 'glob';
import archiver from 'archiver';
import * as path from 'path';

interface IDirectoryConfig {
    sourceDirectory: string;
    targetDirectory: string;
    subFolder: string;
    patterns: string[];
    exclusions: string[];
}
interface IDeployConfig {
    target: string;
    directories: IDirectoryConfig[];
}

async function copyFiles({ sourceDirectory, targetDirectory, subFolder, patterns, exclusions }: IDirectoryConfig) {
    const finalTargetDirectory = path.join(targetDirectory, subFolder);

    await fs.ensureDir(finalTargetDirectory);

    for (const pattern of patterns) {
        const files = glob.sync(pattern, { cwd: sourceDirectory, nodir: true, ignore: exclusions });

        await Promise.all(
            files.map(async file => {
                const srcPath = path.join(sourceDirectory, file);
                const destPath = path.join(finalTargetDirectory, file);
                await fs.copy(srcPath, destPath, { overwrite: true });
                console.log(`Copied ${srcPath} to ${destPath}`);
            })
        );
    }
}

async function zipDirectory(source: string, outPath: string) {
    const archive = archiver('zip', { zlib: { level: 9 } });
    const stream = fs.createWriteStream(outPath);

    return new Promise<void>((resolve, reject) => {
        archive
            .on('warning', err => err.code !== 'ENOENT' && reject(err))
            .on('error', reject)
            .pipe(stream);

        stream.on('close', () => {
            console.log(`Total bytes: ${archive.pointer()}`);
            console.log('Archiving has been completed.');
            resolve();
        });

        archive.glob('**/*', { cwd: source, ignore: ['**/*.zip'], dot: true });
        archive.finalize();
    });
}

async function cleanupDirectories(configs: IDirectoryConfig[], baseDirectory: string) {
    await Promise.all(
        configs.map(async ({ subFolder }) => {
            const dirPath = path.join(baseDirectory, subFolder);
            await fs.remove(dirPath);
            console.log(`Removed directory: ${dirPath}`);
        })
    );
}

async function main() {
    try {
        const configBaseName = process.argv[2] || 'lsp8.app';
        if (!configBaseName) {
            console.error('Please provide the config filename without the .json extension');
            return;
        }

        const configFilePath = path.join('configs', `${configBaseName}.json`);
        const deploymentConfig = (await fs.readJSON(configFilePath)) as IDeployConfig;

        const directoryConfigs = deploymentConfig.directories;

        await Promise.all(directoryConfigs.map(copyFiles));

        const finalZipPath = path.join(directoryConfigs[0].targetDirectory, deploymentConfig.target);
        await zipDirectory(directoryConfigs[0].targetDirectory, finalZipPath);
        console.log('All configurations have been zipped successfully.');

        await cleanupDirectories(directoryConfigs, directoryConfigs[0].targetDirectory);
    } catch (err) {
        console.error(err);
    }
}

(async () => {
    await main();
})();

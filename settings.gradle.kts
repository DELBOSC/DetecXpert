rootProject.name = 'DetectXpert'

// Inclusion des modules principaux
include ':core:config'
include ':core:errors'
include ':core:logging'
include ':core:threading'
include ':core:offline'
include ':core:field-adaptation'
include ':core:integration-engine'
include ':core:device-fusion'

// Modules domain
include ':domain:detection'
include ':domain:user'
include ':domain:mapping'
include ':domain:equipment'
include ':domain:findings'
include ':domain:session'
include ':domain:collaboration'
include ':domain:legal'
include ':domain:club'
include ':domain:competition'
include ':domain:location'
include ':domain:subscription'
include ':domain:terrain'
include ':domain:historical'
include ':domain:archive'
include ':domain:documentation'
include ':domain:safety'

// Modules features
include ':features:tomography'
include ':features:multi-modal'
include ':features:ar'
include ':features:quantum'
include ':features:ai'

// Modules platform
include ':platform:android'
include ':platform:ios'
include ':platform:web'

// Modules tests
include ':tests:integration'
include ':tests:e2e'
include ':tests:performance'

// Automatisation du mapping pour les modules avec tirets
rootProject.children.each { proj -> 
    proj.children.each { subproj ->
        if (subproj.name.contains('-')) {
            def originalName = subproj.name
            subproj.name = subproj.name.replaceAll('-', '_')
            println "Module mapping: ${proj.name}:${originalName} => ${proj.name}:${subproj.name}"
        }
    }
}

// Configuration Gradle
gradle.beforeProject { project ->
    project.setProperty("version", "1.0.0-SNAPSHOT")
    project.setProperty("group", "com.detectxpert")
}
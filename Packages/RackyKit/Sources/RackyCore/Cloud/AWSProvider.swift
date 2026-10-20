import Foundation

/// Adaptador AWS: SÓ o esqueleto. Nenhuma chamada de rede existe no app ainda (BK12-T08, depois do spike da Fase 0 e do OK do dono).
/// Toda operação lança `CloudError.notImplemented`. Esta lista é o contrato do que o adaptador real precisa chamar.
///
/// Credenciais (BK12-T09): `aws login` (credenciais de curta duração, navegador) ou Identity Center/SSO; o app assume o papel criado por
/// CloudFormation quick-create (privilégio mínimo, só recursos com `racky:managed=true`, restrito às regiões habilitadas, mais um alarme
/// de orçamento). Nunca chave de longa duração, nunca permissão de administrador.
///
/// Chamadas necessárias (nome da API -> para quê):
///
/// Conta e papel
/// - `sts:GetCallerIdentity` -> validar a sessão e mostrar a conta/papel na UI.
/// - `cloudformation:CreateStack` / `DescribeStacks` (+ link quick-create `console.aws.amazon.com/cloudformation/home#/stacks/quickcreate`)
///   -> papel mínimo + `AWS::Budgets::Budget` com alerta (o teto REAL do usuário é o do app; o do Budgets é rede de segurança tardia).
///
/// Regiões, tamanhos, preço, cota
/// - `ec2:DescribeRegions` (opt-in status) -> `regions()`; latência medida pelo app (TCP a `ec2.<região>.amazonaws.com`).
/// - `ec2:DescribeInstanceTypes` (filtro `processor-info.supported-architecture=arm64`) -> `shapes(region:)`.
/// - `pricing:GetProducts` (endpoint `us-east-1`/`ap-south-1`, `ServiceCode=AmazonEC2`, Linux, Shared, `preInstalledSw=NA`) ou tabela
///   embutida por versão do app -> `estimate(...)`; somar IPv4 público (US$ 0,005/h) e EBS gp3.
/// - `servicequotas:GetServiceQuota` (`ServiceCode=ec2`, `QuotaCode=L-1216C47A`, vCPUs "Running On-Demand Standard") +
///   `ec2:DescribeInstances` (vCPUs em uso) -> `quota(region:)`.
///
/// Subir o host (`provisionHost`)
/// - `ssm:GetParameter` `/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64` -> AMI por região (Fase 2: AMI própria com Docker e a imagem).
/// - `ec2:CreateSecurityGroup` + `ec2:AuthorizeSecurityGroupIngress` (22/tcp só do IP público do usuário; nada mais; sem egress extra),
///   com tags Racky; reutilizar um por região (`racky-host`). `ec2:DescribeSecurityGroups` para achar o existente.
/// - `ec2:RunInstances`: `InstanceType`, `ImageId`, `UserData` (base64 do cloud-init de `CloudInit`), `SecurityGroupIds`,
///   `InstanceInitiatedShutdownBehavior=terminate` (a chave morta apaga a VM), `BlockDeviceMappings` gp3 com `DeleteOnTermination=true`,
///   `MetadataOptions{HttpTokens=required, HttpPutResponseHopLimit=1, HttpEndpoint=enabled}` (IMDSv2 com 1 salto: os containers NÃO
///   alcançam o metadata, que guarda a chave do host), `TagSpecifications` para `instance` E `volume` (`RackyTags.dictionary`),
///   `MinCount=MaxCount=1`, `ClientToken` (idempotência), sem key pair (a chave entra por `authorized_keys` no cloud-init), IP público.
/// - `ec2:DescribeInstances` (poll até `running` e `PublicIpAddress`) ou waiter `instance_running`.
/// - `ec2:GetConsoleOutput` -> diagnosticar boot que não chega ao SSH.
///
/// Listar e encerrar
/// - `ec2:DescribeInstances` com `Filters` `tag:racky:managed=true` e `tag:racky:owner=<installId>` em CADA região habilitada
///   (pagina por `NextToken`) -> `listHosts`; estados `pending|running|stopping|stopped|shutting-down|terminated` mapeados para `CloudHostState`.
/// - `ec2:TerminateInstances` (condição IAM `aws:ResourceTag/racky:managed=true`) -> `terminateHost`; depois `ec2:DescribeVolumes` por tag
///   para achar volumes soltos (o reaper também os apaga: `ec2:DeleteVolume`).
///
/// Custo real (Fase 2): `ce:GetCostAndUsage` agrupado pela tag `racky:owner` (atraso de horas; só reconcilia, nunca freia).
///
/// Transporte: o SDK da AWS NÃO entra no app sem decisão; opção é EC2 Query + SigV4 próprios (`URLSession`), poucas ações.
public struct AWSProvider: CloudProvider {
    public let id = CloudProviderID.aws

    public init() {}

    private func todo<T>(_ operation: String) throws -> T { throw CloudError.notImplemented("AWSProvider.\(operation)") }

    public func acceptableUsePolicy() async throws -> AcceptableUsePolicy {
        // AWS Acceptable Use Policy (https://aws.amazon.com/aup/): versão = data da página; reconfirmar quando mudar.
        try todo("acceptableUsePolicy")
    }
    public func regions() async throws -> [CloudRegion] { try todo("regions") }
    public func quota(region: String) async throws -> CloudQuota { try todo("quota") }
    public func shapes(region: String) async throws -> [HostShape] { try todo("shapes") }
    public func estimate(shape: HostShape, region: String) async throws -> CostEstimate { try todo("estimate") }
    public func provisionHost(_ request: HostRequest) async throws -> CloudHost { try todo("provisionHost") }
    public func listHosts(tags: [String: String], regions: [String]) async throws -> [CloudHost] { try todo("listHosts") }
    public func terminateHost(id: String, region: String) async throws { throw CloudError.notImplemented("AWSProvider.terminateHost") }
}
